require "test_helper"

class MetricsControllerTest < ActionDispatch::IntegrationTest
  test "requires the configured bearer token" do
    with_metrics_token("secret-token") do
      get metrics_path
      assert_response :unauthorized

      get metrics_path, headers: { "Authorization" => "Bearer wrong" }
      assert_response :unauthorized
    end
  end

  test "returns Prometheus metrics to an authorized collector" do
    with_metrics_token("secret-token") do
      get metrics_path, headers: { "Authorization" => "Bearer secret-token" }

      assert_response :success
      assert_includes response.media_type, "text/plain"
      assert_includes response.body, "rails_http_requests_total"
      assert_includes response.body, "solid_queue_stuck_running_jobs"
    end
  end

  private
    def with_metrics_token(value)
      previous = ENV["METRICS_BEARER_TOKEN"]
      ENV["METRICS_BEARER_TOKEN"] = value
      yield
    ensure
      ENV["METRICS_BEARER_TOKEN"] = previous
    end
end
