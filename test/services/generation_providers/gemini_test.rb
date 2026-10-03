# frozen_string_literal: true

require "test_helper"
require "base64"
require "tempfile"
require "webmock/minitest"

class GenerationProvidersGeminiTest < ActiveSupport::TestCase
  ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions"

  setup { VCR.turn_off!(ignore_cassettes: true) }
  teardown { VCR.turn_on! }

  test "converts chat messages to a stateless Gemini interaction" do
    stub_interaction(text_response("A gentle story", id: "gem_text_1"))
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "page_prompt_revision")

    response = adapter.chat(parameters: {
      model: "gpt-4.1",
      max_tokens: 700,
      temperature: 0.2,
      messages: [
        { role: "developer", content: "Primary rules" },
        { role: "system", content: "Safety rules" },
        { role: "user", content: "A forest walk" },
        { role: "assistant", content: "Earlier example" }
      ]
    })

    assert_equal "A gentle story", response.dig("choices", 0, "message", "content")
    assert_equal "gem_text_1", response["id"]
    assert_equal "gemini-3.8-flash", response["model"]
    assert_requested(:post, ENDPOINT) do |http_request|
      payload = JSON.parse(http_request.body)
      assert_equal "gem-key", http_request.headers["X-Goog-Api-Key"]
      assert_equal false, payload["store"]
      assert_equal "gemini-3.8-flash", payload["model"]
      assert_equal "Primary rules\n\nSafety rules", payload["system_instruction"]
      assert_includes payload["input"], "USER:\nA forest walk"
      assert_includes payload["input"], "ASSISTANT EXAMPLE:\nEarlier example"
      assert_equal 700, payload.dig("generation_config", "max_output_tokens")
      assert_not payload.dig("generation_config").key?("temperature")
      assert_nil payload["response_format"]
    end
  end

  test "requests operation-specific structured story JSON" do
    story = [ { story: "Once", image: "A child in a forest" } ].to_json
    stub_interaction(text_response(story))
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "book_story")

    response = adapter.chat(parameters: { messages: [ { role: "user", content: "Write it" } ] })

    assert_equal story, response.dig("choices", 0, "message", "content")
    assert_requested(:post, ENDPOINT) do |http_request|
      format = JSON.parse(http_request.body).fetch("response_format")
      assert_equal "text", format.fetch("type")
      assert_equal "application/json", format.fetch("mime_type")
      assert_equal "array", format.dig("schema", "type")
      assert_equal %w[story image], format.dig("schema", "items", "required")
    end
  end

  test "uses configurable Gemini text and image models" do
    with_env("GEMINI_TEXT_MODEL" => "gemini-custom-text", "GEMINI_IMAGE_MODEL" => "gemini-custom-image") do
      adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "book_story")

      assert_equal "gemini-custom-text", adapter.model_for(:chat, {})
      assert_equal "gemini-custom-text", adapter.model_for(:moderations, {})
      assert_equal "gemini-custom-image", adapter.model_for(:generate, {})
      assert_equal "gemini-custom-image", adapter.model_for(:edit, {})
    end
  end

  test "generates and edits images with inline reference data" do
    generated = Base64.strict_encode64("generated-image")
    requests = []
    stub_request(:post, ENDPOINT).to_return do |http_request|
      requests << JSON.parse(http_request.body)
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: image_response(generated, id: "gem_image_1").to_json }
    end
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "character_image")

    generated_response = adapter.generate(parameters: { prompt: "One friendly fox", size: "1024x1024" })
    Tempfile.create([ "reference", ".png" ]) do |first|
      first.binmode
      first.write("first-reference")
      first.rewind
      Tempfile.create([ "reference", ".jpg" ]) do |second|
        second.binmode
        second.write("second-reference")
        second.rewind
        edited_response = adapter.edit(parameters: {
          prompt: "Keep both identities", image: [ first, second.path ], size: "1024x1024"
        })
        assert_equal generated, edited_response.dig("data", 0, "b64_json")
      end
    end

    assert_equal generated, generated_response.dig("data", 0, "b64_json")
    assert_equal "gem_image_1", generated_response["id"]
    assert_equal "gemini-3.1-flash-image", requests.first["model"]
    assert_equal [ "text" ], requests.first.fetch("input").map { |entry| entry.fetch("type") }
    assert_equal [ "image", "image", "text" ], requests.second.fetch("input").map { |entry| entry.fetch("type") }
    assert_equal Base64.strict_encode64("first-reference"), requests.second.dig("input", 0, "data")
    assert_equal Base64.strict_encode64("second-reference"), requests.second.dig("input", 1, "data")
    requests.each do |payload|
      assert_equal false, payload["store"]
      assert_equal({ "type" => "image", "mime_type" => "image/png", "aspect_ratio" => "1:1", "image_size" => "1K" },
        payload["response_format"])
    end
  end

  test "normalizes structured character screening with and without a photo" do
    screening = {
      flagged: true,
      categories: {
        hate: false, harassment: false, self_harm: false, sexual: false,
        sexual_minors: false, violence: true, violence_graphic: false
      },
      category_scores: {
        hate: 0.01, harassment: 0.01, self_harm: 0.01, sexual: 0.01,
        sexual_minors: 0.01, violence: 0.9, violence_graphic: 0.2
      }
    }.to_json
    payloads = []
    stub_request(:post, ENDPOINT).to_return do |http_request|
      payloads << JSON.parse(http_request.body)
      { status: 200, headers: { "Content-Type" => "application/json" }, body: text_response(screening).to_json }
    end
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "character_screening")

    text_only = adapter.moderations(parameters: { input: [ { type: "text", text: "A knight" } ] })
    with_photo = adapter.moderations(parameters: { input: [
      { type: "text", text: "A knight" },
      { type: "image_url", image_url: { url: "data:image/png;base64,#{Base64.strict_encode64("photo")}" } }
    ] })

    result = with_photo.fetch("results").sole
    assert_equal true, result["flagged"]
    assert_equal true, result.dig("categories", "violence")
    assert_equal 0.9, result.dig("category_scores", "violence")
    assert_equal [ "text", "image" ], result.dig("category_applied_input_types", "violence")
    assert_equal [ "text" ], text_only.dig("results", 0, "category_applied_input_types", "violence")
    assert_equal [ "text" ], payloads.first.fetch("input").map { |entry| entry.fetch("type") }
    assert_equal [ "image", "text" ], payloads.second.fetch("input").map { |entry| entry.fetch("type") }
    assert_equal "object", payloads.second.dig("response_format", "schema", "type")
  end

  test "normalizes explicit safety rejection without exposing provider prose" do
    request = stub_request(:post, ENDPOINT).to_return(
      status: 400,
      headers: { "Content-Type" => "application/json", "x-goog-request-id" => "gem_blocked_1" },
      body: { error: { code: "SAFETY", message: "Private provider policy explanation" } }.to_json
    )
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "character_image")

    error = assert_raises(GenerationProviders::ContentRejected) do
      adapter.generate(parameters: { prompt: "blocked", size: "1024x1024" })
    end

    assert_equal 400, error.response[:status]
    assert_equal "moderation_blocked", error.response.dig(:body, "error", "code")
    assert_equal "gem_blocked_1", error.response.dig(:headers, "x-request-id")
    assert_not_includes error.response.dig(:body, "error", "message"), "Private"
    assert_requested request
  end

  test "rejects completed responses without the requested output block" do
    stub_interaction({ id: "gem_empty", model: "gemini-3.8-flash", status: "completed", steps: [] })
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "book_story")

    assert_raises(GenerationProviders::InvalidResponse) { adapter.chat(parameters: { messages: [] }) }
  end

  test "propagates timeout rate-limit and server failures" do
    adapter = GenerationProviders::Gemini.new(api_key: "gem-key", operation: "book_story")

    stub_request(:post, ENDPOINT).to_timeout
    assert_raises(Faraday::ConnectionFailed) { adapter.chat(parameters: { messages: [] }) }
    WebMock.reset!

    [
      [ { status: 429, body: { error: { code: "RESOURCE_EXHAUSTED" } }.to_json,
        headers: { "Content-Type" => "application/json" } }, Faraday::TooManyRequestsError ],
      [ { status: 503, body: { error: { code: "UNAVAILABLE" } }.to_json,
        headers: { "Content-Type" => "application/json" } }, Faraday::ServerError ]
    ].each do |stubbed_response, error_class|
      stub_request(:post, ENDPOINT).to_return(stubbed_response)
      assert_raises(error_class) { adapter.chat(parameters: { messages: [] }) }
      WebMock.reset!
    end
  end

  private

  def stub_interaction(body)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: body.to_json
    )
  end

  def text_response(text, id: "gem_text")
    {
      id: id,
      model: "gemini-3.8-flash",
      status: "completed",
      steps: [ { type: "model_output", content: [ { type: "text", text: text } ] } ]
    }
  end

  def image_response(data, id: "gem_image")
    {
      id: id,
      model: "gemini-3.1-flash-image",
      status: "completed",
      steps: [ { type: "model_output", content: [ { type: "image", mime_type: "image/png", data: data } ] } ]
    }
  end

  def with_env(values)
    original = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
