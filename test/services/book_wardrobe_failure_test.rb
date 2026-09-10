require "test_helper"

class BookWardrobeFailureTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "distinguishes temporary rate limits from exhausted credits" do
    error = Faraday::TooManyRequestsError.new("rate limit", status: 429,
      body: { "error" => { "code" => "rate_limit_exceeded", "type" => "tokens" } })
    failure = BookWardrobeFailure.details(error, stage: "story")
    assert_equal "wardrobe_provider_rate_limit", failure[:type]
    assert_equal "tokens", failure[:metadata]["provider_type"]
  end

  test "parses string error bodies and does not expose provider text or arbitrary headers" do
    error = Faraday::TooManyRequestsError.new("quota", status: 429,
      headers: { "authorization" => "private", "x-request-id" => "req_example" },
      body: { "error" => { "code" => "insufficient_quota", "message" => "private provider text" } }.to_json)
    failure = BookWardrobeFailure.details(error, stage: "wardrobe_plan")
    assert_equal "wardrobe_provider_quota", failure[:type]
    assert_equal "req_example", failure[:metadata]["request_id"]
    assert_not_includes failure.to_json, "private"
  end
end
