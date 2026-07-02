# frozen_string_literal: true

require "json"
require "sinatra/base"
require "time"

require_relative "services/fizzy_client"
require_relative "services/memory_cache"
require_relative "services/sprint_dashboard"

module ScrumManager
  class App < Sinatra::Base
    set :root, File.dirname(__FILE__)
    set :public_folder, proc { File.join(root, "public") }
    set :views, proc { File.join(root, "views") }
    set :show_exceptions, false
    set :raise_errors, false

    configure do
      set :cache, MemoryCache.new(default_ttl: Integer(ENV.fetch("CACHE_TTL_SECONDS", "5")))
    end

    helpers do
      def h(value)
        Rack::Utils.escape_html(value.to_s)
      end

      def selected?(actual, expected)
        actual.to_s == expected.to_s ? "active" : nil
      end

      def json_payload(payload)
        JSON.pretty_generate(payload)
      end
    end

    before do
      @app_name = "Scrum Manager"
    end

    get "/" do
      @sprints = cached("sprints") { fizzy_client.sprint_tags }
      erb :index
    end

    get "/sprints/:tag" do
      @sprint_tag = params[:tag]
      @selected_assignee = params.fetch("assignee", "Everyone")
      @selected_board = params.fetch("board", "All Boards")
      base_dashboard = cached_dashboard(@sprint_tag)
      @assignees = base_dashboard.assignees
      @boards = base_dashboard.boards
      @dashboard = base_dashboard.filtered(assignee: @selected_assignee, board: @selected_board)

      erb :sprint
    end

    get "/api/sprints/:tag/cards" do
      content_type :json

      dashboard = cached_dashboard(params[:tag]).filtered(
        assignee: params.fetch("assignee", "Everyone"),
        board: params.fetch("board", "All Boards")
      )

      json_payload(dashboard.to_h)
    end

    not_found do
      status 404
      @error_title = "Page not found"
      @error_message = "The requested dashboard page does not exist."
      erb :error
    end

    error FizzyClient::ConfigurationError do
      status 500
      @error_title = "Fizzy is not configured"
      @error_message = env["sinatra.error"].message
      erb :error
    end

    error FizzyClient::RequestError do
      status 502
      @error_title = "Fizzy request failed"
      @error_message = env["sinatra.error"].message
      erb :error
    end

    error do
      status 500
      @error_title = "Unexpected error"
      @error_message = env["sinatra.error"].message
      erb :error
    end

    private

    def fizzy_client
      @fizzy_client ||= FizzyClient.new(
        token: ENV["FIZZY_TOKEN"],
        account_slug: ENV["FIZZY_ACCOUNT_SLUG"]
      )
    end

    def cached_dashboard(tag_title)
      cached(["dashboard", tag_title]) do
        cards = fizzy_client.cards_for_sprint(tag_title)
        SprintDashboard.new(tag_title: tag_title, cards: cards)
      end
    end

    def cached(key, &block)
      settings.cache.fetch(key, &block)
    end
  end
end
