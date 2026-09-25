require "test_helper"

class Observability::SolidQueueMetricsTest < ActiveSupport::TestCase
  FakeSource = Data.define(:ready, :failed, :claimed_at, :oldest_ready_at, :finished_since) do
    def ready_count = ready
    def failed_count = failed
    def claimed_started_at = claimed_at
    def oldest_ready_created_at = oldest_ready_at
    def finished_count_since(_time) = finished_since
  end

  test "reports queue health and jobs running longer than fifteen minutes" do
    now = Time.utc(2026, 9, 25, 12, 0, 0)
    source = FakeSource.new(
      ready: 4,
      failed: 2,
      claimed_at: [ now - 901, now - 899 ],
      oldest_ready_at: now - 30,
      finished_since: 6
    )

    snapshot = Observability::SolidQueueMetrics.new(source: source, now: -> { now }).snapshot

    assert_equal 4, snapshot.fetch(:queue_depth)
    assert_equal 30, snapshot.fetch(:oldest_ready_seconds)
    assert_equal 2, snapshot.fetch(:failed_total)
    assert_equal 1, snapshot.fetch(:stuck_running)
    assert_equal 0.1, snapshot.fetch(:processing_rate_per_second)
  end
end
