# frozen_string_literal: true

require "time"

module ScrumManager
  class SprintReports
    DEFAULT_SPRINT_DURATION_DAYS = 10

    def initialize(sprint_duration_days: DEFAULT_SPRINT_DURATION_DAYS)
      @sprint_duration_days = sprint_duration_days
    end

    def sprint_report(snapshots:, start_at:, board:, assignee:, now: Time.now.utc)
      points = Array(snapshots).filter_map do |snapshot|
        observed_at = time_value(snapshot["observed_at"] || snapshot[:observed_at])
        next unless observed_at

        cards = Array(snapshot["cards"] || snapshot[:cards]).select do |card|
          card_matches?(card, board, assignee)
        end
        done = cards.count { |card| card_value(card, "status") == "Done" }
        { at: observed_at, scope: cards.length, done: done, remaining: cards.length - done }
      end.sort_by { |point| point[:at] }

      sprint_start = time_value(start_at)
      sprint_end = sprint_start && sprint_start + (@sprint_duration_days * 86_400)
      initial_commitment = points.first&.fetch(:scope, nil)

      {
        snapshots: points,
        initial_commitment: initial_commitment,
        duration_days: @sprint_duration_days,
        sprint_start: sprint_start&.iso8601,
        sprint_end: sprint_end&.iso8601,
        generated_at: now.utc.iso8601,
        history_status: history_status(points.length),
        chart: {
          actual_remaining: chart_points(points, sprint_start) do |point|
            point[:scope].zero? ? 0 : (point[:remaining].to_f / point[:scope] * 100).round(1)
          end,
          completed: chart_points(points, sprint_start) { |point| point[:done] },
          total_scope: chart_points(points, sprint_start) { |point| point[:scope] },
          ideal_remaining: ideal_points(initial_commitment, sprint_start, sprint_end)
        }
      }
    end

    def velocity_report(sprints:, snapshots_by_sprint:, board:, assignee:)
      ordered_sprints = Array(sprints).sort_by do |sprint|
        time_value(sprint["created_at"] || sprint[:created_at]) || Time.at(0).utc
      end
      active_sprint_id = ordered_sprints.last && (ordered_sprints.last["id"] || ordered_sprints.last[:id]).to_s

      rows = ordered_sprints.filter_map do |sprint|
        sprint_id = (sprint["id"] || sprint[:id]).to_s
        snapshots = Array(snapshots_by_sprint[sprint_id]).sort_by do |snapshot|
          time_value(snapshot["observed_at"] || snapshot[:observed_at]) || Time.at(0).utc
        end
        next if snapshots.empty?

        commitment_cards = filtered_cards(snapshots.first, board, assignee)
        latest_cards = filtered_cards(snapshots.last, board, assignee)
        {
          sprint: sprint["title"] || sprint[:title],
          committed: commitment_cards.length,
          scope: latest_cards.length,
          completed: latest_cards.count { |card| card_value(card, "status") == "Done" },
          active: sprint_id == active_sprint_id
        }
      end
      completed_sprints = rows.reject { |row| row[:active] }

      {
        sprints: rows,
        average_completed: completed_sprints.empty? ? nil : (completed_sprints.sum { |row| row[:completed] }.to_f / completed_sprints.length).round(1),
        average_sprint_count: completed_sprints.length
      }
    end

    private

    def chart_points(points, start_at)
      return [] unless start_at

      points.map do |point|
        { x: ((point[:at] - start_at) / 86_400.0).round(2), y: yield(point) }
      end
    end

    def ideal_points(commitment, start_at, end_at)
      return [] unless commitment && start_at && end_at

      [
        { x: 0, y: 100 },
        { x: @sprint_duration_days, y: 0 }
      ]
    end

    def history_status(point_count)
      return "No snapshots recorded yet" if point_count.zero?
      return "Baseline only; progress history starts with the next sync" if point_count == 1

      "Observed in #{point_count} sync snapshots; earlier history is unavailable"
    end

    def filtered_cards(snapshot, board, assignee)
      Array(snapshot["cards"] || snapshot[:cards]).select do |card|
        card_matches?(card, board, assignee)
      end
    end

    def card_matches?(card, board, assignee)
      return false if board != "All Boards" && card_value(card, "board_name") != board

      assignees = Array(card_value(card, "assignee_names"))
      return true if assignee == "Everyone"
      return assignees.empty? if assignee == "Unassigned"

      assignees.include?(assignee)
    end

    def card_value(card, key)
      card[key] || card[key.to_sym]
    end

    def time_value(value)
      return value if value.respond_to?(:utc)
      return nil if value.to_s.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
  end
end