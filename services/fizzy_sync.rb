# frozen_string_literal: true

require "time"

module ScrumManager
  class FizzySync
    def initialize(client:, store:, logger: $stdout)
      @client = client
      @store = store
      @logger = logger
    end

    def sync_all
      started_at = Time.now.utc
      stats = { tags: 0, sprints: 0, cards: 0 }

      all_tags = @client.tags
      @store.upsert_tags(all_tags)
      stats[:tags] = all_tags.length

      sprint_tags = all_tags
        .select { |tag| tag.fetch("title", "").downcase.start_with?("sprint") }
        .sort_by { |tag| tag["created_at"].to_s }
        .reverse
      @store.upsert_sprint_tags(sprint_tags)
      stats[:sprints] = sprint_tags.length
      snapshot_payloads = []

      sprint_tags.each do |tag|
        cards = @client.cards_for_sprint_tag(tag)
        @store.replace_sprint_cards(tag, cards)
        snapshot_payloads << [tag, cards]
        stats[:cards] += cards.length
        @logger.puts "Synced #{cards.length} cards for #{tag.fetch("title", tag.fetch("id"))}"
      end

      finished_at = Time.now.utc
      snapshot_payloads.each do |tag, cards|
        @store.record_sprint_snapshot(tag: tag, cards_payload: cards, observed_at: finished_at)
      end
      @store.record_sync!(started_at: started_at, finished_at: finished_at, stats: stats)
      stats
    rescue StandardError => e
      @store.record_sync!(started_at: started_at, finished_at: Time.now.utc, stats: stats, error: "#{e.class}: #{e.message}")
      raise
    end
  end
end
