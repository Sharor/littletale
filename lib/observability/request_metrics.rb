module Observability
  class RequestMetrics
    DURATION_BUCKETS = [ 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10 ].freeze

    attr_reader :requests, :duration

    def initialize(registry: Prometheus::Client.registry)
      @requests = registry.counter(:rails_http_requests_total, docstring: "Total Rails HTTP requests", labels: %i[method route status])
      @duration = registry.histogram(:rails_http_request_duration_seconds, docstring: "Rails HTTP request duration in seconds", labels: %i[method route], buckets: DURATION_BUCKETS)
    end

    def observe(method:, route:, status:, elapsed:)
      labels = { method: method, route: route }
      requests.increment(labels: labels.merge(status: status.to_s))
      duration.observe(elapsed, labels: labels)
    end

    class Middleware
      def initialize(app, metrics: Observability.request_metrics)
        @app = app
        @metrics = metrics
      end

      def call(env)
        return @app.call(env) if env["PATH_INFO"] == "/metrics"

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = 500
        response = @app.call(env)
        status = response.first
        response
      ensure
        if started_at
          @metrics.observe(
            method: env.fetch("REQUEST_METHOD", "UNKNOWN"),
            route: normalized_route(env["action_dispatch.route_uri_pattern"]),
            status: status,
            elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          )
        end
      end

      private
        def normalized_route(pattern)
          pattern.present? ? pattern.sub(/\(\.?:format\)\z/, "") : "unmatched"
        end
    end
  end
end
