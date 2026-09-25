require "test_helper"

class Observability::RequestMetricsTest < ActiveSupport::TestCase
  test "records request count and duration with bounded labels" do
    registry = Prometheus::Client::Registry.new
    metrics = Observability::RequestMetrics.new(registry: registry)
    app = ->(_env) { [ 201, {}, [ "created" ] ] }
    middleware = Observability::RequestMetrics::Middleware.new(app, metrics: metrics)

    status, = middleware.call(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/books/123",
      "action_dispatch.route_uri_pattern" => "/books/:id(.:format)"
    )

    assert_equal 201, status
    assert_equal 1, registry.get(:rails_http_requests_total).get(labels: {
      method: "POST", route: "/books/:id", status: "201"
    })
    assert_equal 1, registry.get(:rails_http_request_duration_seconds).get(labels: {
      method: "POST", route: "/books/:id"
    }).fetch("+Inf")
  end

  test "records raised requests as status 500 and re-raises" do
    registry = Prometheus::Client::Registry.new
    metrics = Observability::RequestMetrics.new(registry: registry)
    middleware = Observability::RequestMetrics::Middleware.new(
      ->(_env) { raise "boom" }, metrics: metrics
    )

    assert_raises(RuntimeError) { middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/boom") }
    assert_equal 1, registry.get(:rails_http_requests_total).get(labels: {
      method: "GET", route: "unmatched", status: "500"
    })
  end
end
