# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class GenerationProvidersClientTest < ActiveSupport::TestCase
  FakeAdapter = Struct.new(:provider_name, :result, :error, :during_call, keyword_init: true) do
    def model_for(_capability, _parameters) = "#{provider_name}-model"

    def chat(parameters:)
      during_call&.call
      raise error if error

      result
    end

    alias generate chat
    alias edit chat
    alias moderations chat
  end

  setup do
    GenerationProviderRequest.delete_all
    GenerationProviderSetting.delete_all
  end

  test "records a successful request without prompt or response content" do
    response = { "id" => "req_safe-1", "choices" => [ { "message" => { "content" => "private story" } } ] }
    client = build_client(openai: FakeAdapter.new(provider_name: "openai", result: response))

    assert_equal response, client.chat(parameters: { model: "ignored", messages: [ { content: "private prompt" } ] })

    request = GenerationProviderRequest.sole
    assert_equal "openai", request.provider
    assert_equal "story", request.operation
    assert_equal "openai-model", request.model
    assert_equal "succeeded", request.outcome
    assert_equal "req_safe-1", request.external_request_id
    assert_not_includes request.attributes.values, "private prompt"
    assert_not_includes request.attributes.values, "private story"
  end

  test "captures the provider when a request starts" do
    setting = GenerationProviderSetting.current
    openai = FakeAdapter.new(provider_name: "openai",
      result: { "choices" => [ { "message" => { "content" => "OpenAI result" } } ] },
      during_call: -> { setting.change_mode!("gemini") })
    gemini = FakeAdapter.new(provider_name: "gemini",
      result: { "choices" => [ { "message" => { "content" => "Gemini result" } } ] })
    client = build_client(openai: openai, gemini: gemini)

    assert_equal "OpenAI result", client.chat(parameters: {})["choices"].first["message"]["content"]
    assert_equal "openai", GenerationProviderRequest.last.provider
    assert_equal "Gemini result", client.chat(parameters: {})["choices"].first["message"]["content"]
    assert_equal "gemini", GenerationProviderRequest.last.provider
  end

  test "classifies provider errors without changing the raised object" do
    cases = {
      GenerationProviders::ContentRejected.new("blocked", response: response(status: 400)) => "content_rejected",
      GenerationProviders::InvalidResponse.new("malformed") => "invalid_response",
      Faraday::UnauthorizedError.new("unauthorized", response(status: 401)) => "configuration_error",
      Faraday::BadRequestError.new("bad", response(status: 400)) => "request_error",
      Faraday::TooManyRequestsError.new("limited", response(status: 429)) => "availability_failure",
      Faraday::ServerError.new("down", response(status: 503)) => "availability_failure",
      Faraday::TimeoutError.new("timeout") => "availability_failure",
      Faraday::ConnectionFailed.new("offline") => "availability_failure"
    }

    cases.each do |error, expected_outcome|
      adapter = FakeAdapter.new(provider_name: "openai", error: error)
      raised = assert_raises(error.class) { build_client(openai: adapter).chat(parameters: {}) }

      assert_same error, raised
      assert_equal expected_outcome, GenerationProviderRequest.order(:id).last.outcome
    end
  end

  test "rejects a malformed success response as invalid" do
    client = build_client(openai: FakeAdapter.new(provider_name: "openai", result: { "id" => "req_bad" }))

    assert_raises(GenerationProviders::InvalidResponse) { client.chat(parameters: {}) }
    request = GenerationProviderRequest.sole
    assert_equal "invalid_response", request.outcome
    assert_equal "req_bad", request.external_request_id
  end

  test "supports the OpenAI-compatible image and moderation methods" do
    image = { "data" => [ { "b64_json" => "aW1hZ2U=" } ] }
    moderation = { "results" => [ { "flagged" => false } ] }
    adapter = FakeAdapter.new(provider_name: "openai", result: image)
    client = build_client(openai: adapter)

    assert_equal image, client.images.generate(parameters: {})
    assert_equal image, client.images.edit(parameters: {})
    adapter.result = moderation
    assert_equal moderation, client.moderations(parameters: {})
  end

  test "tracking failure does not mask a successful response" do
    response = { "choices" => [ { "message" => { "content" => "kept" } } ] }
    client = build_client(openai: FakeAdapter.new(provider_name: "openai", result: response))
    logger = Minitest::Mock.new
    logger.expect(:error, true) { |message| message.include?("Generation provider tracking failed") }

    Rails.stub :logger, logger do
      GenerationProviderRequest.stub :record!, ->(**) { raise ActiveRecord::StatementInvalid, "tracking unavailable" } do
        assert_equal response, client.chat(parameters: {})
      end
    end
    logger.verify
  end

  test "tracking failure does not mask the original provider exception" do
    provider_error = Faraday::TimeoutError.new("provider timeout")
    client = build_client(openai: FakeAdapter.new(provider_name: "openai", error: provider_error))
    logger = Object.new
    logger.define_singleton_method(:error) { |_message| true }

    raised = Rails.stub(:logger, logger) do
      GenerationProviderRequest.stub :record!, ->(**) { raise ActiveRecord::StatementInvalid, "tracking unavailable" } do
        assert_raises(Faraday::TimeoutError) { client.chat(parameters: {}) }
      end
    end
    assert_same provider_error, raised
  end

  test "drops unsafe provider request identifiers" do
    response = { "id" => "unsafe id with spaces", "choices" => [ { "message" => { "content" => "ok" } } ] }

    build_client(openai: FakeAdapter.new(provider_name: "openai", result: response)).chat(parameters: {})

    assert_nil GenerationProviderRequest.sole.external_request_id
  end

  private

  def build_client(adapters)
    GenerationProviders::Client.new(operation: "story", adapter_factory: ->(provider, _operation) { adapters.fetch(provider.to_sym) })
  end

  def response(status:)
    { status: status, headers: {}, body: {} }
  end
end
