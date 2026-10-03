module HealthChecks
  class Base
    def initialize(wall_clock: -> { Time.current }, monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @wall_clock = wall_clock
      @monotonic_clock = monotonic_clock
    end

    private
      def start_check
        @started_at = @monotonic_clock.call
        @checked_at = @wall_clock.call
      end

      def result(name:, status:, message:)
        Result.new(
          name: name,
          status: status,
          message: message,
          checked_at: @checked_at.iso8601,
          duration_ms: ((@monotonic_clock.call - @started_at) * 1_000).round
        )
      end
  end
end
