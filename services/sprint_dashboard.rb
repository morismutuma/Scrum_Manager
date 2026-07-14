# frozen_string_literal: true

require "time"

module ScrumManager
  class SprintDashboard
    SPECIAL_STATUS_ORDER = ["Not Now", "Maybe"].freeze
    DONE_STATUS = "Done"
    EVERYONE = "Everyone"
    ALL_BOARDS = "All Boards"
    UNASSIGNED = "Unassigned"
    EFFORT_TAGS = [
      "#1 day",
      "#1 week",
      "#2 days",
      "#2 hours",
      "#2 weeks",
      "#3 days",
      "#3 hours",
      "#4 hours",
      "#5 days",
      "#a few hours",
      "#an hour or less"
    ].freeze

    attr_reader :tag_title, :cards, :generated_at

    def initialize(tag_title:, cards:, generated_at: Time.now, normalized: false)
      @tag_title = tag_title
      @cards = normalized ? Array(cards) : Array(cards).map { |card| normalize_card(card) }
      @generated_at = generated_at
    end

    def filtered(assignee: EVERYONE, board: ALL_BOARDS)
      filtered_cards = cards.select { |card| matches_assignee?(card, assignee) }
      filtered_cards = filtered_cards.select { |card| card[:board_name] == board } unless board == ALL_BOARDS

      self.class.new(tag_title: tag_title, cards: filtered_cards, generated_at: generated_at, normalized: true)
    end

    def assignees
      names = cards.flat_map { |card| card[:assignees] }.uniq.sort
      [EVERYONE, *names, UNASSIGNED]
    end

    def boards
      [ALL_BOARDS, *cards.map { |card| card[:board_name] }.uniq.sort]
    end

    def board_sections
      cards
        .group_by { |card| card[:board_name] }
        .sort_by { |board_name, _| board_name.downcase }
        .map do |board_name, board_cards|
          statuses = ordered_statuses(board_cards)
          {
            name: board_name,
            count: board_cards.length,
            columns: statuses.map do |status|
              status_cards = board_cards.select { |card| card[:status] == status }
              {
                name: status,
                key: status_key(status),
                count: status_cards.length,
                cards: status_cards
              }
            end
          }
        end
    end

    def to_h
      {
        tag_title: tag_title,
        generated_at: generated_at.iso8601,
        generated_at_label: generated_at.strftime("%H:%M:%S"),
        cards_count: cards.length,
        assignees: assignees,
        boards: boards,
        board_sections: board_sections
      }
    end

    private

    def normalize_card(card)
      {
        id: card["id"],
        number: card["number"],
        title: card["title"].to_s,
        url: card["url"].to_s,
        status: dashboard_status(card),
        board_name: card.dig("board", "name") || "No Board",
        column_name: card.dig("column", "name"),
        assignees: normalize_assignees(card["assignees"]),
        tags: normalize_tags(card["tags"]),
        last_active_at: card["last_active_at"],
        last_active_label: relative_time(card["last_active_at"]),
        closed: card["closed"] == true,
        postponed: card["postponed"] == true
      }
    end

    def dashboard_status(card)
      return DONE_STATUS if card["closed"] == true
      return "Not Now" if card["postponed"] == true

      column = card.dig("column", "name")
      return column unless column.to_s.empty?

      "Maybe"
    end

    def normalize_assignees(assignees)
      Array(assignees).filter_map { |assignee| assignee["name"].to_s unless assignee["name"].to_s.empty? }
    end

    def normalize_tags(tags)
      normalized_tags = Array(tags).filter_map do |tag|
        label = tag_label(tag)
        next if label.empty?
        next if sprint_number_tag?(label)

        {
          label: label,
          key: status_key(label.delete_prefix("#")),
          kind: tag_kind(label)
        }
      end

      normalized_tags.sort_by.with_index do |tag, index|
        [tag[:kind] == "effort" ? 0 : 1, index]
      end
    end

    def tag_label(tag)
      case tag
      when Hash
        tag["title"].to_s
      else
        tag.to_s
      end
    end

    def tag_kind(label)
      normalized = label.downcase.strip
      return "epic" if normalized == "epic" || normalized == "#epic"
      return "subtasks" if ["subtask", "subtasks", "#subtask", "#subtasks"].include?(normalized)
      return "effort" if EFFORT_TAGS.include?(normalized)

      "default-#{stable_tag_bucket(normalized)}"
    end

    def sprint_number_tag?(label)
      label.downcase.strip.match?(/\Asprint.*\d\z/)
    end

    def stable_tag_bucket(value)
      value.bytes.sum % 6
    end

    def matches_assignee?(card, assignee)
      case assignee
      when EVERYONE
        true
      when UNASSIGNED
        card[:assignees].empty?
      else
        card[:assignees].include?(assignee)
      end
    end

    def ordered_statuses(board_cards)
      statuses = board_cards.map { |card| card[:status] }.uniq
      dynamic = statuses - SPECIAL_STATUS_ORDER - [DONE_STATUS]
      SPECIAL_STATUS_ORDER.select { |status| statuses.include?(status) } +
        dynamic.sort_by(&:downcase) +
        ([DONE_STATUS] & statuses)
    end

    def status_key(status)
      status.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    def relative_time(timestamp)
      return "Never" if timestamp.to_s.empty?

      seconds = Time.now - Time.parse(timestamp)
      return "Just now" if seconds < 60
      return "#{(seconds / 60).floor} mins ago" if seconds < 3600
      return "#{(seconds / 3600).floor} hours ago" if seconds < 86_400

      "#{(seconds / 86_400).floor} days ago"
    rescue ArgumentError
      timestamp.to_s
    end
  end
end
