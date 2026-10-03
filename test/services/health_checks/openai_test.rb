require "test_helper"

class HealthChecksOpenaiTest < ActiveSupport::TestCase
  Response = Data.define(:code)

  test "reports a connected account using the non-generation models endpoint" do
    transport = lambda do |uri:, headers:, open_timeout:, read_timeout:|
      assert_equal URI("https://api.openai.com/v1/models"), uri
      assert_equal "Bearer token-value", headers.fetch("Authorization")
      assert_equal 3, open_timeout
      assert_equal 5, read_timeout
      Response.new("200")
    end

    result = HealthChecks::Openai.new(
      access_token: "token-value",
      transport: transport,
      wall_clock: -> { Time.zone.parse("2026-10-03 10:00:00") },
      monotonic_clock: sequence_clock(8.0, 8.014)
    ).call

    assert_equal "openai", result.name
    assert_equal "connected", result.status
    assert_equal "Authentication and API access confirmed.", result.message
    assert_equal "2026-10-03T10:00:00Z", result.checked_at
    assert_equal 14, result.duration_ms
  end

  test "the HTTP transport disables automatic retries and bounds timeouts" do
    http = Struct.new(:use_ssl, :open_timeout, :read_timeout, :max_retries, :request_received) do
      def start
        yield self
      end

      def request(request)
        self.request_received = request
        Response.new("200")
      end
    end.new
    factory = lambda do |host, port|
      assert_equal "api.openai.com", host
      assert_equal 443, port
      http
    end
    transport = HealthChecks::Openai::HttpTransport.new(http_factory: factory)

    response = transport.call(
      uri: URI("https://api.openai.com/v1/models"),
      headers: { "Authorization" => "Bearer safe-token" },
      open_timeout: 3,
      read_timeout: 5
    )

    assert_equal "200", response.code
    assert http.use_ssl
    assert_equal 3, http.open_timeout
    assert_equal 5, http.read_timeout
    assert_equal 0, http.max_retries
    assert_equal "GET", http.request_received.method
    assert_equal "/v1/models", http.request_received.path
  end

  test "reports a missing token without making a request" do
    transport = ->(**) { flunk "request must not be made" }

    result = HealthChecks::Openai.new(access_token: nil, transport: transport).call

    assert_equal "not_configured", result.status
    assert_equal "Missing OPENAI_ACCESS_TOKEN.", result.message
  end

  test "reports rejected credentials without including the response body or token" do
    transport = ->(**) { Response.new("401") }

    result = HealthChecks::Openai.new(access_token: "secret-token", transport: transport).call

    assert_equal "failed", result.status
    assert_equal "OpenAI rejected the configured credentials.", result.message
    assert_no_match(/secret-token/, result.message)
  end

  test "reports request timeouts safely" do
    transport = ->(**) { raise Net::ReadTimeout, "secret timeout detail" }

    result = HealthChecks::Openai.new(access_token: "secret-token", transport: transport).call

    assert_equal "failed", result.status
    assert_equal "The OpenAI request timed out.", result.message
    assert_no_match(/secret/, result.message)
  end

  private
    def sequence_clock(*values)
      -> { values.shift || values.last }
    end
end
