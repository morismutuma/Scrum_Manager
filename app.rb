# frozen_string_literal: true

require "json"
require "sinatra/base"
require "time"

require_relative "services/fizzy_client"
require_relative "services/fizzy_sync"
require_relative "services/mongo_store"
require_relative "services/sprint_dashboard"

module ScrumManager
  class App < Sinatra::Base
    set :root, File.dirname(__FILE__)
    set :public_folder, proc { File.join(root, "public") }
    set :views, proc { File.join(root, "views") }
    set :show_exceptions, false
    set :raise_errors, false

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

      def local_time(value)
        time =
          if value.respond_to?(:getlocal)
            value
          else
            Time.parse(value.to_s)
          end

        time.getlocal.strftime("%Y-%m-%d %H:%M:%S")
      end
    end

    before do
      @app_name = "Scrum Manager"
    end

    get "/" do
      @sprints = mongo_store.sprint_tags
      @last_sync = mongo_store.last_sync
      erb :index
    end

    get "/sprints/:tag" do
      @sprint_tag = params[:tag]
      @selected_assignee = params.fetch("assignee", "Everyone")
      @selected_board = params.fetch("board", "All Boards")
      base_dashboard = dashboard_from_store(@sprint_tag)
      @assignees = base_dashboard.assignees
      @boards = base_dashboard.boards
      @dashboard = base_dashboard.filtered(assignee: @selected_assignee, board: @selected_board)
      @last_sync = mongo_store.last_sync

      erb :sprint
    end

    get "/api/sprints/:tag/cards" do
      content_type :json

      dashboard = dashboard_from_store(params[:tag]).filtered(
        assignee: params.fetch("assignee", "Everyone"),
        board: params.fetch("board", "All Boards")
      )

      json_payload(dashboard.to_h)
    end

    post "/sync" do
      sync_service.sync_all
      redirect "/"
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

    error MongoStore::ConfigurationError do
      status 500
      @error_title = "MongoDB is not configured"
      @error_message = env["sinatra.error"].message
      erb :error
    end

    error Mongo::Error do
      status 503
      @error_title = "MongoDB request failed"
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

    def mongo_store
      @mongo_store ||= MongoStore.new(
        uri: ENV["MONGODB_URI"],
        database_name: ENV.fetch("MONGODB_DATABASE", "scrum_manager"),
        server_selection_timeout: Float(ENV.fetch("MONGODB_SERVER_SELECTION_TIMEOUT", "2"))
      )
    end

    def sync_service
      @sync_service ||= FizzySync.new(client: fizzy_client, store: mongo_store)
    end

    def dashboard_from_store(tag_title)
      cards = mongo_store.cards_for_sprint(tag_title)
      SprintDashboard.new(tag_title: tag_title, cards: cards)
    end
  end
end
