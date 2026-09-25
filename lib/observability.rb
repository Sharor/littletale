require "prometheus/client"
require_relative "observability/request_metrics"
require_relative "observability/solid_queue_metrics"

module Observability
  class << self
    attr_reader :registry, :request_metrics

    def setup!
      @registry = Prometheus::Client::Registry.new
      @request_metrics = RequestMetrics.new(registry: @registry)
      register_queue_metrics
    end

    def refresh_queue_metrics
      values = SolidQueueMetrics.new.snapshot
      @queue_metrics.each { |name, metric| metric.set(values.fetch(name)) }
      @queue_available.set(1)
    rescue ActiveRecord::ActiveRecordError
      @queue_available.set(0)
      @queue_metrics.each_value { |metric| metric.set(0) }
    end

    private
      def register_queue_metrics
        definitions = {
          queue_depth: [ :solid_queue_depth, "Jobs ready to run" ],
          oldest_ready_seconds: [ :solid_queue_oldest_ready_job_seconds, "Age of the oldest ready job" ],
          failed_total: [ :solid_queue_failed_jobs, "Jobs with exhausted retries" ],
          stuck_running: [ :solid_queue_stuck_running_jobs, "Jobs running longer than fifteen minutes" ],
          processing_rate_per_second: [ :solid_queue_processing_rate_per_second, "Jobs completed per second over the last minute" ]
        }
        @queue_metrics = definitions.transform_values do |name, docstring|
          @registry.gauge(name, docstring: docstring)
        end
        @queue_available = @registry.gauge(:solid_queue_metrics_available, docstring: "Whether Solid Queue metrics could be read")
      end
  end
end
