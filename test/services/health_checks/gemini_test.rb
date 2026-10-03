# frozen_string_literal: true

require "test_helper"

class HealthChecksGeminiTest < ActiveSupport::TestCase
  Response = Data.define(:code)

  test "reports a connected account using a non-generation model metadata endpoint" do
    transport = lambda do |uri:, headers:, open_timeout:, read_timeout:|
      assert_equal URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash"), uri
      assert_equal "gemini-key", headers.fetch("x-goog-api-key")
      assert_equal 3, open_timeout
      assert_equal 5, read_timeout
      Response.new("200")
    end

    result = HealthChecks::Gemini.new(
      api_key: "gemini-key",
      model: "gemini-3.8-flash",
      transport: transport,
      wall_clock: -> { Time.zone.parse("2026-10-03 10:00:00") },
      monotonic_clock: sequence_clock(8.0, 8.018)
    ).call

    assert_equal "gemini", result.name
    assert_equal "connected", result.status
    assert_equal "Authentication and model access confirmed.", result.message
    assert_equal "2026-10-03T10:00:00Z", result.checked_at
    assert_equal 18, result.duration_ms
  end

  test "the HTTP transport performs one bounded GET without retries" do
    http = Struct.new(:use_ssl, :open_timeout, :read_timeout, :max_retries, :request_received) do
      def start
        yield self
      end

      def request(request)
        self.request_received = request
        Response.new("200")
      end
    end.new
    factory = ->(host, port) { assert_equal "generativelanguage.googleapis.com", host; assert_equal 443, port; http }
    transport = HealthChecks::Gemini::HttpTransport.new(http_factory: factory)

    response = transport.call(
      uri: URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash"),
      headers: { "x-goog-api-key" => "safe-key" },
      open_timeout: 3,
      read_timeout: 5
    )

    assert_equal "200", response.code
    assert http.use_ssl
    assert_equal 3, http.open_timeout
    assert_equal 5, http.read_timeout
    assert_equal 0, http.max_retries
    assert_equal "GET", http.request_received.method
    assert_equal "/v1beta/models/gemini-3.8-flash", http.request_received.path
  end

  test "reports a missing key without making a request" do
    transport = ->(**) { flunk "request must not be made" }

    result = HealthChecks::Gemini.new(api_key: nil, transport: transport).call

    assert_equal "not_configured", result.status
    assert_equal "Missing GEMINI_API_KEY.", result.message
  end

  test "reports rejected credentials and timeouts without provider details" do
    rejected = HealthChecks::Gemini.new(
      api_key: "secret-key",
      transport: ->(**) { Response.new("403") }
    ).call
    timed_out = HealthChecks::Gemini.new(
      api_key: "secret-key",
      transport: ->(**) { raise Net::ReadTimeout, "secret timeout detail" }
    ).call

    assert_equal "failed", rejected.status
    assert_equal "Gemini rejected the configured credentials.", rejected.message
    assert_equal "failed", timed_out.status
    assert_equal "The Gemini request timed out.", timed_out.message
    assert_no_match(/secret/, "#{rejected.message} #{timed_out.message}")
  end

  test "does not add metadata checks to generation request history" do
    assert_no_difference("GenerationProviderRequest.count") do
      HealthChecks::Gemini.new(api_key: "gemini-key", transport: ->(**) { Response.new("200") }).call
    end
  end

  private

  def sequence_clock(*values)
    -> { values.shift || values.last }
  end
end
