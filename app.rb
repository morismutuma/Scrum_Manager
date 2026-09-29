# # frozen_string_literal: true

# require "json"
# require "sinatra/base"
# require "time"

# require_relative "services/mongo_store"
# require_relative "services/sprint_dashboard"

# module ScrumManager
#   class App < Sinatra::Base
#     set :root, File.dirname(__FILE__)
#     set :public_folder, proc { File.join(root, "public") }
#     set :views, proc { File.join(root, "views") }
#     set :show_exceptions, false
#     set :raise_errors, false

#     helpers do
#       def h(value)
#         Rack::Utils.escape_html(value.to_s)
#       end

#       def selected?(actual, expected)
#         actual.to_s == expected.to_s ? "active" : nil
#       end

#       def json_payload(payload)
#         JSON.pretty_generate(payload)
#       end

#       def local_time(value)
#         time =
#           if value.respond_to?(:getlocal)
#             value
#           else
#             Time.parse(value.to_s)
#           end

#         time.getlocal.strftime("%Y-%m-%d %H:%M:%S")
#       end

#       def sprint_display_name(value)
#         value.to_s.sub(/\Asprint\s*(\d+)\z/i, 'Sprint \1')
#       end
#     end

#     before do
#       @app_name = "Scrum Manager"
#     end

#     get "/" do
#       @sprints = mongo_store.sprint_tags
#       @sprint_card_counts = mongo_store.sprint_card_counts
#       @last_sync = mongo_store.last_sync
#       erb :index
#     end

#     get "/sprints/:tag" do
#       @sprint_tag = params[:tag]
#       @selected_assignee = params.fetch("assignee", "Everyone")
#       @selected_board = params.fetch("board", "All Boards")
#       base_dashboard = dashboard_from_store(@sprint_tag)
#       @assignees = base_dashboard.assignees
#       @boards = base_dashboard.boards
#       @dashboard = base_dashboard.filtered(assignee: @selected_assignee, board: @selected_board)
#       @last_sync = mongo_store.last_sync

#       erb :sprint
#     end

#     get "/api/sprints/:tag/cards" do
#       content_type :json

#       dashboard = dashboard_from_store(params[:tag]).filtered(
#         assignee: params.fetch("assignee", "Everyone"),
#         board: params.fetch("board", "All Boards")
#       )

#       json_payload(dashboard.to_h)
#     end

#     post "/sync" do
#       sync_service.sync_all
#       redirect "/"
#     end

#     not_found do
#       status 404
#       @error_title = "Page not found"
#       @error_message = "The requested dashboard page does not exist."
#       erb :error
#     end

#     error FizzyClient::ConfigurationError do
#       status 500
#       @error_title = "Fizzy is not configured"
#       @error_message = env["sinatra.error"].message
#       erb :error
#     end

#     error FizzyClient::RequestError do
#       status 502
#       @error_title = "Fizzy request failed"
#       @error_message = env["sinatra.error"].message
#       erb :error
#     end

#     error MongoStore::ConfigurationError do
#       status 500
#       @error_title = "MongoDB is not configured"
#       @error_message = env["sinatra.error"].message
#       erb :error
#     end

#     error Mongo::Error do
#       status 503
#       @error_title = "MongoDB request failed"
#       @error_message = env["sinatra.error"].message
#       erb :error
#     end

#     error do
#       status 500
#       @error_title = "Unexpected error"
#       @error_message = env["sinatra.error"].message
#       erb :error
#     end

#     private

#     def fizzy_client
#       @fizzy_client ||= FizzyClient.new(
#         token: ENV["FIZZY_TOKEN"],
#         account_slug: ENV["FIZZY_ACCOUNT_SLUG"]
#       )
#     end

#     def mongo_store
#       @mongo_store ||= MongoStore.new(
#         uri: ENV["MONGODB_URI"],
#         database_name: ENV.fetch("MONGODB_DATABASE", "scrum_manager"),
#         server_selection_timeout: Float(ENV.fetch("MONGODB_SERVER_SELECTION_TIMEOUT", "2"))
#       )
#     end

#     def sync_service
#       @sync_service ||= FizzySync.new(client: fizzy_client, store: mongo_store)
#     end

#     def dashboard_from_store(tag_title)
#       cards = mongo_store.cards_for_sprint(tag_title)
#       SprintDashboard.new(tag_title: tag_title, cards: cards)
#     end
#   end
# end





#wiht the route added 
# frozen_string_literal: true

require "json"
require "omniauth"
require "omniauth-google-oauth2"
require "rack/session/cookie"
require "sinatra/base"
require "time"

require_relative "services/fizzy_client"
require_relative "services/fizzy_sync"
require_relative "services/mongo_store"
require_relative "services/sprint_dashboard"
require_relative "services/sprint_reports"

module ScrumManager
  class App < Sinatra::Base
    set :root, File.dirname(__FILE__)
    set :public_folder, proc { File.join(root, "public") }
    set :views, proc { File.join(root, "views") }
    set :show_exceptions, false
    set :raise_errors, false

    session_secret = ENV["SESSION_SECRET"].to_s
    if session_secret.bytesize < 64
      raise ArgumentError, "SESSION_SECRET must be at least 64 bytes; generate one with `openssl rand -hex 64`."
    end

    use Rack::Session::Cookie,
        key: "rack.session",
        path: "/",
        secret: session_secret

    use OmniAuth::Builder do
      provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"]
    end

    helpers do
      def current_user
        session[:user]
      end

      def authenticate!
        redirect "/auth/google_oauth2" unless current_user
      end

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

      def extract_tag_name(sprint)
        case sprint
        when Hash
          sprint["title"] || sprint[:title] || sprint["name"] || sprint[:name] || sprint.to_s
        else
          sprint.to_s
        end
      end

      def sprint_display_name(value)
        name = extract_tag_name(value)
        name.sub(/\Asprint\s*(\d+)\z/i, 'Sprint \1')
      end
    end

    # helpers do
    #   def h(value)
    #     Rack::Utils.escape_html(value.to_s)
    #   end

    #   def selected?(actual, expected)
    #     actual.to_s == expected.to_s ? "active" : nil
    #   end

    #   def json_payload(payload)
    #     JSON.pretty_generate(payload)
    #   end

    #   def local_time(value)
    #     time =
    #       if value.respond_to?(:getlocal)
    #         value
    #       else
    #         Time.parse(value.to_s)
    #       end

    #     time.getlocal.strftime("%Y-%m-%d %H:%M:%S")
    #   end

    #   def sprint_display_name(value)
    #     value.to_s.sub(/\Asprint\s*(\d+)\z/i, 'Sprint \1')
    #   end
    # end

    before do
      @app_name = "Scrum Manager"
    end

    get "/auth/google_oauth2/callback" do
      auth = request.env["omniauth.auth"]
      session[:user] = {
        name: auth.info.name,
        email: auth.info.email,
        image: auth.info.image
      }
      redirect "/"
    end

    get "/auth/logout" do
      session.clear
      redirect "/"
    end

    get "/" do
      @sprints = mongo_store.sprint_tags
      @sprint_card_counts = mongo_store.sprint_card_counts
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

    get "/reports" do
      raw_sprints = mongo_store.sprint_tags
      @sprints = raw_sprints.map { |s| extract_tag_name(s) }.uniq

      @selected_sprint = extract_tag_name(params.fetch("sprint", @sprints.first || "sprint1"))
      @selected_assignee = params.fetch("assignee", "Everyone")
      @selected_board = params.fetch("board", "All Boards")

      base_dashboard = dashboard_from_store(@selected_sprint)
      @assignees = base_dashboard.assignees
      @boards = base_dashboard.boards
      @dashboard = base_dashboard.filtered(assignee: @selected_assignee, board: @selected_board)
      @last_sync = mongo_store.last_sync

      erb :reports
    end

    get "/api/reports/burndown" do
      content_type :json

      sprint_tag = extract_tag_name(params.fetch("sprint", "sprint1"))
      selected_assignee = params.fetch("assignee", "Everyone")
      selected_board = params.fetch("board", "All Boards")
      report_service = SprintReports.new(
        sprint_duration_days: Integer(ENV.fetch("SPRINT_DURATION_DAYS", SprintReports::DEFAULT_SPRINT_DURATION_DAYS.to_s))
      )
      sprint_tags = mongo_store.sprint_tags
      sprint = sprint_tags.find { |tag| extract_tag_name(tag).casecmp?(sprint_tag) }
      snapshots = mongo_store.snapshots_for_sprint(sprint_tag)
      sprint_report = report_service.sprint_report(
        snapshots: snapshots,
        start_at: sprint && sprint["created_at"],
        board: selected_board,
        assignee: selected_assignee
      )
      snapshots_by_sprint = mongo_store.all_sprint_snapshots.group_by { |snapshot| snapshot["sprint_tag_id"].to_s }
      velocity = report_service.velocity_report(
        sprints: sprint_tags,
        snapshots_by_sprint: snapshots_by_sprint,
        board: selected_board,
        assignee: selected_assignee
      )
      latest = sprint_report[:snapshots].last || {}
      json_payload({
        sprint: sprint_tag,
        assignee: selected_assignee,
        board: selected_board,
        start_date: sprint_report[:sprint_start],
        end_date: sprint_report[:sprint_end],
        duration_days: sprint_report[:duration_days],
        initial_commitment: sprint_report[:initial_commitment],
        total_cards: latest[:scope] || 0,
        done_cards: latest[:done] || 0,
        remaining_cards: latest[:remaining] || 0,
        history_status: sprint_report[:history_status],
        chart: sprint_report[:chart],
        velocity: velocity,
        generated_at: Time.now.strftime("%H:%M:%S")
      })
    end

    get "/cards/:id/edit" do
      authenticate!
      @card = mongo_store.find_card(params[:id])
      erb :edit_card
    end

    post "/cards/:id/update" do
      authenticate!
      card_id = params[:id]
      new_title = params[:title]
      new_status = params[:status]

      mongo_store.update_card(card_id, title: new_title, status: new_status)
      fizzy_client.update_card(card_id, title: new_title, status: new_status)

      redirect "/"
    end

    # get "/reports" do
    #   @sprints = mongo_store.sprint_tags
    #   @selected_sprint = params.fetch("sprint", @sprints.first || "sprint1")
    #   @selected_assignee = params.fetch("assignee", "Everyone")
    #   @selected_board = params.fetch("board", "All Boards")

    #   base_dashboard = dashboard_from_store(@selected_sprint)
    #   @assignees = base_dashboard.assignees
    #   @boards = base_dashboard.boards
    #   @dashboard = base_dashboard.filtered(assignee: @selected_assignee, board: @selected_board)
    #   @last_sync = mongo_store.last_sync

    #   erb :reports
    # end

    # get "/api/reports/burndown" do
    #   content_type :json

    #   sprint_tag = params.fetch("sprint", "sprint1")
    #   selected_assignee = params.fetch("assignee", "Everyone")
    #   selected_board = params.fetch("board", "All Boards")

    #   dashboard = dashboard_from_store(sprint_tag).filtered(
    #     assignee: selected_assignee,
    #     board: selected_board
    #   )

    #   total_cards = dashboard.cards.length
    #   done_cards = dashboard.cards.count { |c| c[:status] == "Done" }
    #   remaining_cards = total_cards - done_cards

    #   days = (1..10).map { |i| "Day #{i}" }
    #   ideal_step = total_cards.to_f / (days.length - 1)
    #   ideal_line = days.each_with_index.map { |_, idx| [total_cards - (ideal_step * idx), 0].max.round(1) }
    #   actual_line = [total_cards, total_cards, total_cards - (done_cards > 1 ? 1 : 0), remaining_cards]

    #   json_payload({
    #     sprint: sprint_tag,
    #     assignee: selected_assignee,
    #     board: selected_board,
    #     total_cards: total_cards,
    #     done_cards: done_cards,
    #     remaining_cards: remaining_cards,
    #     chart: {
    #       labels: days,
    #       ideal: ideal_line,
    #       actual: actual_line
    #     },
    #     generated_at: Time.now.strftime("%H:%M:%S")
    #   })
    # end

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