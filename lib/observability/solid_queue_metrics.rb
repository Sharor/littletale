module Observability
  class SolidQueueMetrics
    STUCK_AFTER = 15.minutes
    RATE_WINDOW = 1.minute

    def initialize(source: Source.new, now: -> { Time.current })
      @source = source
      @now = now
    end

    def snapshot
      current_time = @now.call
      {
        queue_depth: @source.ready_count,
        oldest_ready_seconds: age(current_time, @source.oldest_ready_created_at),
        failed_total: @source.failed_count,
        stuck_running: @source.claimed_started_at.count { |started_at| started_at < current_time - STUCK_AFTER },
        processing_rate_per_second: @source.finished_count_since(current_time - RATE_WINDOW).fdiv(RATE_WINDOW.to_i)
      }
    end

    private
      def age(current_time, timestamp)
        timestamp ? [ current_time - timestamp, 0 ].max : 0
      end

    class Source
      def ready_count = SolidQueue::ReadyExecution.count
      def failed_count = SolidQueue::FailedExecution.count
      def claimed_started_at = SolidQueue::ClaimedExecution.pluck(:created_at)
      def oldest_ready_created_at = SolidQueue::ReadyExecution.minimum(:created_at)
      def finished_count_since(time) = SolidQueue::Job.where(finished_at: time..).count
    end
  end
end
