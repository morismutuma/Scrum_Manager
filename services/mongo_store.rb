# frozen_string_literal: true

require "mongo"
require "time"

module ScrumManager
  class MongoStore
    class ConfigurationError < StandardError; end

    DEFAULT_URI = "mongodb://127.0.0.1:27017"

    def initialize(uri:, database_name:, server_selection_timeout: 2)
      @uri = uri.to_s.strip
      @uri = DEFAULT_URI if @uri.empty?
      @database_name = database_name.to_s.strip

      raise ConfigurationError, "Set MONGODB_DATABASE in your environment." if @database_name.empty?

      @client = Mongo::Client.new(
        @uri,
        database: @database_name,
        server_selection_timeout: server_selection_timeout
      )
      ensure_indexes
    end

    def sprint_tags
      sprints
        .find(active: true)
        .sort(created_at: -1, title_downcase: -1)
        .map { |doc| from_doc(doc.fetch("raw", {})) }
    end

    def sprint_card_counts
      cards.aggregate(
        [
          { "$unwind" => "$sprint_tag_ids" },
          { "$group" => { _id: "$sprint_tag_ids", count: { "$sum" => 1 } } }
        ]
      ).each_with_object({}) do |doc, counts|
        counts[doc.fetch("_id")] = doc.fetch("count")
      end
    end

    def cards_for_sprint(tag_title)
      sprint = sprint_by_title(tag_title)
      return [] unless sprint

      cards
        .find(sprint_tag_ids: sprint.fetch("id"))
        .sort(board_name: 1, status_sort: 1, last_active_at_time: -1)
        .map { |doc| from_doc(doc.fetch("raw", {})) }
    end

    def snapshots_for_sprint(tag_title)
      sprint = sprint_by_title(tag_title)
      return [] unless sprint

      sprint_snapshots_collection
        .find(sprint_tag_id: sprint.fetch("id"))
        .sort(observed_at: 1)
        .map { |doc| from_doc(doc) }
    end

    def all_sprint_snapshots
      sprint_snapshots_collection
        .find
        .sort(observed_at: 1)
        .map { |doc| from_doc(doc) }
    end

    def record_sprint_snapshot(tag:, cards_payload:, observed_at: Time.now.utc)
      sprint_snapshots_collection.insert_one(
        sprint_tag_id: tag.fetch("id"),
        sprint_title: tag.fetch("title", ""),
        observed_at: observed_at,
        cards: cards_payload.map do |card|
          {
            number: card["number"],
            board_name: card.dig("board", "name") || "No Board",
            assignee_names: Array(card["assignees"]).filter_map { |assignee| assignee["name"] },
            status: dashboard_status(card)
          }
        end
      )
    end

    def last_sync
      sync_runs.find(type: "fizzy_full_sync").sort(finished_at: -1).first
    end

    def upsert_sprint_tags(tags)
      now = Time.now.utc
      active_ids = tags.map { |tag| tag.fetch("id") }

      tags.each do |tag|
        sprints.update_one(
          { id: tag.fetch("id") },
          {
            "$set" => {
              id: tag.fetch("id"),
              title: tag.fetch("title", ""),
              title_downcase: tag.fetch("title", "").downcase,
              created_at: parse_time(tag["created_at"]),
              active: true,
              raw: tag,
              synced_at: now
            }
          },
          upsert: true
        )
      end

      sprints.update_many({ id: { "$nin" => active_ids } }, { "$set" => { active: false, synced_at: now } })
    end

    def upsert_tags(tags_payload)
      now = Time.now.utc
      active_ids = tags_payload.map { |tag| tag.fetch("id") }

      tags_payload.each do |tag|
        tags.update_one(
          { id: tag.fetch("id") },
          {
            "$set" => {
              id: tag.fetch("id"),
              title: tag.fetch("title", ""),
              title_downcase: tag.fetch("title", "").downcase,
              created_at: parse_time(tag["created_at"]),
              active: true,
              raw: tag,
              synced_at: now
            }
          },
          upsert: true
        )
      end

      tags.update_many({ id: { "$nin" => active_ids } }, { "$set" => { active: false, synced_at: now } })
    end

    def replace_sprint_cards(tag, cards_payload)
      now = Time.now.utc
      tag_id = tag.fetch("id")
      seen_numbers = []

      cards_payload.each do |card|
        number = card["number"]
        next unless number

        seen_numbers << number
        assignee_names = Array(card["assignees"]).filter_map { |assignee| assignee["name"] }
        status = dashboard_status(card)

        cards.update_one(
          { number: number },
          {
            "$set" => {
              number: number,
              title: card["title"].to_s,
              board_name: card.dig("board", "name") || "No Board",
              column_name: card.dig("column", "name"),
              status: status,
              status_sort: status_sort(status),
              assignee_names: assignee_names,
              last_active_at_time: parse_time(card["last_active_at"]),
              raw: card,
              synced_at: now
            },
            "$addToSet" => {
              sprint_tag_ids: tag_id,
              sprint_tag_titles: tag.fetch("title", "")
            }
          },
          upsert: true
        )
      end

      cards.update_many(
        { sprint_tag_ids: tag_id, number: { "$nin" => seen_numbers } },
        {
          "$pull" => {
            sprint_tag_ids: tag_id,
            sprint_tag_titles: tag.fetch("title", "")
          },
          "$set" => { synced_at: now }
        }
      )
    end

    def record_sync!(started_at:, finished_at:, stats:, error: nil)
      sync_runs.insert_one(
        type: "fizzy_full_sync",
        started_at: started_at,
        finished_at: finished_at,
        stats: stats,
        error: error
      )
    end

    private

    attr_reader :client

    def sprints
      client[:sprints]
    end

    def cards
      client[:cards]
    end

    def tags
      client[:tags]
    end

    def sync_runs
      client[:sync_runs]
    end

    def sprint_snapshots_collection
      client[:sprint_snapshots]
    end

    def sprint_by_title(tag_title)
      sprints.find(title_downcase: tag_title.to_s.downcase, active: true).first
    end

    def ensure_indexes
      sprints.indexes.create_one({ id: 1 }, unique: true)
      sprints.indexes.create_one({ title_downcase: 1 })
      sprints.indexes.create_one({ active: 1 })
      cards.indexes.create_one({ number: 1 }, unique: true)
      cards.indexes.create_one({ sprint_tag_ids: 1 })
      cards.indexes.create_one({ board_name: 1 })
      tags.indexes.create_one({ id: 1 }, unique: true)
      tags.indexes.create_one({ title_downcase: 1 })
      tags.indexes.create_one({ active: 1 })
      sprint_snapshots_collection.indexes.create_one({ sprint_tag_id: 1, observed_at: 1 })
      sync_runs.indexes.create_one({ type: 1, finished_at: -1 })
    end

    def dashboard_status(card)
      return "Done" if card["closed"] == true
      return "Not Now" if card["postponed"] == true

      column = card.dig("column", "name")
      return column unless column.to_s.empty?

      "Maybe"
    end

    def status_sort(status)
      case status
      when "Not Now" then 0
      when "Maybe" then 1
      when "Done" then 99
      else 50
      end
    end

    def parse_time(value)
      return nil if value.to_s.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def from_doc(value)
      case value
      when Hash
        value.transform_keys(&:to_s).transform_values { |item| from_doc(item) }
      when Array
        value.map { |item| from_doc(item) }
      when Time
        value.iso8601
      else
        value
      end
    end
  end
end
