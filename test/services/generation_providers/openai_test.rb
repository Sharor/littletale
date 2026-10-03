# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class GenerationProvidersOpenaiTest < ActiveSupport::TestCase
  test "passes chat moderation and image requests through unchanged" do
    calls = []
    images = Object.new
    images.define_singleton_method(:generate) { |parameters:| calls << [ :generate, parameters ]; { "data" => [ { "url" => "https://example.test/image" } ] } }
    images.define_singleton_method(:edit) { |parameters:| calls << [ :edit, parameters ]; { "data" => [ { "b64_json" => "aW1hZ2U=" } ] } }
    raw_client = Object.new
    raw_client.define_singleton_method(:chat) { |parameters:| calls << [ :chat, parameters ]; { "choices" => [ { "message" => { "content" => "story" } } ] } }
    raw_client.define_singleton_method(:moderations) { |parameters:| calls << [ :moderations, parameters ]; { "results" => [ { "flagged" => false } ] } }
    raw_client.define_singleton_method(:images) { images }
    adapter = OpenAI::Client.stub(:new, raw_client) { GenerationProviders::Openai.new }

    assert_equal "story", adapter.chat(parameters: { model: "gpt-text" })["choices"].first["message"]["content"]
    assert_equal false, adapter.moderations(parameters: { model: "moderation" })["results"].first["flagged"]
    assert adapter.generate(parameters: { model: "gpt-image" }).dig("data", 0, "url")
    assert adapter.edit(parameters: { model: "gpt-image" }).dig("data", 0, "b64_json")
    assert_equal [ :chat, :moderations, :generate, :edit ], calls.map(&:first)
  end

  test "reports the requested model and preserves provider exceptions" do
    error = Faraday::ConnectionFailed.new("offline")
    raw_client = Object.new
    raw_client.define_singleton_method(:chat) { |parameters:| raise error }
    adapter = OpenAI::Client.stub(:new, raw_client) { GenerationProviders::Openai.new(access_token: "token") }

    assert_equal "gpt-4.1", adapter.model_for(:chat, { model: "gpt-4.1" })
    assert_same error, assert_raises(Faraday::ConnectionFailed) { adapter.chat(parameters: {}) }
  end
end
