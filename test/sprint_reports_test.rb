# frozen_string_literal: true

require "minitest/autorun"
require_relative "../services/sprint_reports"

class SprintReportsTest < Minitest::Test
  def setup
    @reports = ScrumManager::SprintReports.new(sprint_duration_days: 14)
    @cards = [
      { "board_name" => "Client A", "assignee_names" => ["Sam"], "status" => "In Progress" },
      { "board_name" => "Client A", "assignee_names" => [], "status" => "Done" },
      { "board_name" => "Client B", "assignee_names" => ["Sam"], "status" => "Done" }
    ]
  end

  def test_default_sprint_duration_is_ten_days
    report = ScrumManager::SprintReports.new.sprint_report(
      snapshots: [],
      start_at: "2026-09-01T00:00:00Z",
      board: "All Boards",
      assignee: "Everyone"
    )

    assert_equal 10, report[:duration_days]
    assert_equal "2026-09-11T00:00:00Z", report[:sprint_end]
  end

  def test_scope_changes_and_reopened_cards_are_reflected_in_snapshots
    snapshots = [
      snapshot("2026-09-01T00:00:00Z", @cards),
      snapshot("2026-09-02T00:00:00Z", @cards.drop(1).map { |card| card.merge("status" => "In Progress") }),
      snapshot("2026-09-03T00:00:00Z", @cards + [
        { "board_name" => "Client A", "assignee_names" => ["Sam"], "status" => "In Progress" }
      ])
    ]

    report = @reports.sprint_report(
      snapshots: snapshots,
      start_at: "2026-08-30T00:00:00Z",
      board: "Client A",
      assignee: "Everyone"
    )

    assert_equal [{ x: 2.0, y: 2 }, { x: 3.0, y: 1 }, { x: 4.0, y: 3 }], report.dig(:chart, :total_scope)
    assert_equal [{ x: 2.0, y: 1 }, { x: 3.0, y: 0 }, { x: 4.0, y: 1 }], report.dig(:chart, :completed)
    assert_equal [{ x: 2.0, y: 50.0 }, { x: 3.0, y: 100.0 }, { x: 4.0, y: 66.7 }], report.dig(:chart, :actual_remaining)
    assert_equal 2, report[:initial_commitment]
    assert_equal [{ x: 0, y: 100 }, { x: 14, y: 0 }], report.dig(:chart, :ideal_remaining)
  end

  def test_incomplete_history_is_not_invented
    report = @reports.sprint_report(
      snapshots: [],
      start_at: nil,
      board: "All Boards",
      assignee: "Everyone"
    )

    assert_equal "No snapshots recorded yet", report[:history_status]
    assert_nil report[:initial_commitment]
    assert_empty report.dig(:chart, :ideal_remaining)
    assert_empty report.dig(:chart, :actual_remaining)

    baseline = @reports.sprint_report(
      snapshots: [snapshot("2026-09-01T00:00:00Z", @cards)],
      start_at: "2026-08-30T00:00:00Z",
      board: "All Boards",
      assignee: "Everyone"
    )
    assert_equal "Baseline only; progress history starts with the next sync", baseline[:history_status]
    assert_equal [{ x: 2.0, y: 33.3 }], baseline.dig(:chart, :actual_remaining)
  end

  def test_velocity_average_excludes_newest_active_sprint
    sprints = [
      { "id" => "old", "title" => "Sprint 1", "created_at" => "2026-08-01T00:00:00Z" },
      { "id" => "current", "title" => "Sprint 2", "created_at" => "2026-09-01T00:00:00Z" }
    ]
    snapshots = {
      "old" => [snapshot("2026-08-01T00:00:00Z", @cards), snapshot("2026-08-15T00:00:00Z", @cards)],
      "current" => [snapshot("2026-09-01T00:00:00Z", @cards)]
    }

    report = @reports.velocity_report(
      sprints: sprints,
      snapshots_by_sprint: snapshots,
      board: "Client A",
      assignee: "Everyone"
    )

    assert_equal [2, 2], report[:sprints].map { |row| row[:committed] }
    assert_equal [2, 2], report[:sprints].map { |row| row[:scope] }
    assert_equal [1, 1], report[:sprints].map { |row| row[:completed] }
    assert_equal 1, report[:average_sprint_count]
    assert_equal 1.0, report[:average_completed]
  end

  private

  def snapshot(observed_at, cards)
    { "observed_at" => observed_at, "cards" => cards }
  end
end