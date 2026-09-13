# frozen_string_literal: true

require "test_helper"
require "base64"
require "webmock/minitest"

class CharacterImageGenerationTest < ActiveSupport::TestCase
  Assessment = Data.define(:prompt, :generation_model, :photo)

  class Photo
    def initialize(bytes, attached: true)
      @bytes = bytes
      @attached = attached
    end

    def attached?
      @attached
    end

    def download
      @bytes
    end
  end

  GENERATED_BYTES = "generated image bytes".b
  GIF_BYTES = Base64.strict_decode64("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")

  setup do
    VCR.turn_off!(ignore_cassettes: true)
  end

  teardown do
    VCR.turn_on!
  end

  test "edits a photo snapshot with its exact prompt and returns decoded image bytes" do
    request = stub_request(:post, "https://api.openai.com/v1/images/edits")
      .with do |provider_request|
        body = provider_request.body
        body.include?('name="prompt"') && body.include?("A child explorer") &&
          body.include?('name="model"') && body.include?("gpt-image-1") &&
          body.include?('name="size"') && body.include?("1024x1024") &&
          body.include?('filename="character-source') && body.include?(".png\"") &&
          body.include?("\x89PNG".b)
      end
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          id: "img_edit_123",
          data: [ { b64_json: Base64.strict_encode64(GENERATED_BYTES) } ]
        }.to_json
      )
    assessment = Assessment.new(
      prompt: "A child explorer",
      generation_model: "gpt-image-1",
      photo: Photo.new(GIF_BYTES)
    )

    result = CharacterImageGeneration.call(assessment)

    assert_equal GENERATED_BYTES, result.fetch(:io).read
    assert_equal Encoding::BINARY, result.fetch(:io).external_encoding
    assert_equal "character.png", result.fetch(:filename)
    assert_equal "image/png", result.fetch(:content_type)
    assert_equal "img_edit_123", result.fetch(:request_id)
    assert_requested request, times: 1
  end

  test "generates from a description snapshot and downloads the returned URL" do
    provider_request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .with(
        body: {
          prompt: "A friendly red fox",
          model: "dall-e-3",
          size: "1024x1024",
          quality: "standard",
          n: 1
        }.to_json
      )
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          data: [ { url: "https://images.example.test/character.png" } ]
        }.to_json
      )
    download_request = stub_request(:get, "https://images.example.test/character.png")
      .to_return(status: 200, headers: { "Content-Type" => "image/png" }, body: GENERATED_BYTES)
    assessment = Assessment.new(
      prompt: "A friendly red fox",
      generation_model: "dall-e-3",
      photo: Photo.new("", attached: false)
    )

    result = CharacterImageGeneration.call(assessment)

    assert_equal GENERATED_BYTES, result.fetch(:io).read
    assert_nil result.fetch(:request_id)
    assert_requested provider_request, times: 1
    assert_requested download_request, times: 1
  end

  test "generates a saved description request with GPT Image and decodes its response" do
    character = characters(:hernandes)
    request = CharacterImageRequest.submit!(character)
    assessment = request.assessment
    stub_request(:post, "https://api.openai.com/v1/images/generations")
      .with do |http_request|
        payload = JSON.parse(http_request.body)
        assert_equal "gpt-image-1", payload["model"]
        assert_equal "auto", payload["quality"]
        assert_equal payload, assessment.reload.metadata.fetch("generation_request").fetch("parameters")
        assert_not_equal assessment.prompt, payload["prompt"]
        assert_includes payload["prompt"], "wholesome"
        assert_no_match(/sex(?:ual)?/i, payload["prompt"])
        true
      end
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: [ { b64_json: Base64.strict_encode64(GENERATED_BYTES) } ] }.to_json)

    assert_equal GENERATED_BYTES, CharacterImageGeneration.call(assessment).fetch(:io).read
  end

  test "uses a filter-safe provider prompt for the rejected teen description" do
    character = characters(:hernandes)
    character.update!(age: 14, gender: "Girl", ethnicity: "White", hair_color: "Blond",
      hair_style: "Braids", eye_color: "Blue", roles: [])
    assessment = CharacterImageRequest.submit!(character).assessment
    stub_request(:post, "https://api.openai.com/v1/images/generations")
      .with do |http_request|
        prompt = JSON.parse(http_request.body).fetch("prompt")
        assert_includes prompt, "wholesome family storybook"
        assert_includes prompt, "14-year-old"
        assert_includes prompt, "ordinary age-appropriate everyday clothing"
        assert_no_match(/sex(?:ual)?/i, prompt)
        true
      end
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: [ { b64_json: Base64.strict_encode64(GENERATED_BYTES) } ] }.to_json)

    assert_equal GENERATED_BYTES, CharacterImageGeneration.call(assessment).fetch(:io).read
  end

  test "retries a sexual-category false positive once with a reduced description prompt" do
    character = characters(:hernandes)
    character.update!(age: 14, gender: "Girl", ethnicity: "White", hair_color: "Blond",
      hair_style: "Braids", eye_color: "Blue", roles: [])
    assessment = CharacterImageRequest.submit!(character).assessment
    calls = 0
    provider_request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return do |http_request|
        calls += 1
        if calls == 1
          { status: 400, headers: { "Content-Type" => "application/json", "x-request-id" => "req_false_positive" },
            body: { error: { code: "moderation_blocked", category: "sexual" } }.to_json }
        else
          prompt = JSON.parse(http_request.body).fetch("prompt")
          assert_includes prompt, "Simple family storybook portrait"
          assert_no_match(/sex(?:ual)?/i, prompt)
          { status: 200, headers: { "Content-Type" => "application/json" },
            body: { data: [ { b64_json: Base64.strict_encode64(GENERATED_BYTES) } ] }.to_json }
        end
      end

    result = CharacterImageGeneration.call(assessment)

    assert_equal GENERATED_BYTES, result.fetch(:io).read
    assert_equal [ { "code" => "moderation_blocked", "request_id" => "req_false_positive", "category" => "sexual" } ],
      result.fetch(:prior_refusals)
    assert_requested provider_request, times: 2
  end

  test "retries a category-free content filter once for a structured description" do
    assessment = CharacterImageRequest.submit!(characters(:hernandes)).assessment
    provider_request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return(
        { status: 400, headers: { "Content-Type" => "application/json" },
          body: { error: { code: "content_filter" } }.to_json },
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { data: [ { b64_json: Base64.strict_encode64(GENERATED_BYTES) } ] }.to_json }
      )

    assert_equal GENERATED_BYTES, CharacterImageGeneration.call(assessment).fetch(:io).read
    assert_requested provider_request, times: 2
  end

  test "stops after the reduced description prompt is refused and retains both refusals" do
    character = characters(:hernandes)
    assessment = CharacterImageRequest.submit!(character).assessment
    calls = 0
    provider_request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return do
        calls += 1
        { status: 400,
          headers: { "Content-Type" => "application/json", "x-request-id" => "req_refusal_#{calls}" },
          body: { error: { code: "moderation_blocked", category: "sexual" } }.to_json }
      end

    error = assert_raises(CharacterImageGeneration::Refused) do
      CharacterImageGeneration.call(assessment)
    end

    assert_equal CharacterImageGeneration::DESCRIPTION_PROMPT_VERSION,
      error.metadata["description_prompt_version"]
    assert_equal "req_refusal_2", error.metadata["request_id"]
    assert_equal "req_refusal_1", error.metadata.dig("prior_refusals", 0, "request_id")
    assert_requested provider_request, times: 2
  end

  test "raises a refusal with a supported public reason and sanitized provider metadata" do
    request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json", "x-request-id" => "req_refused_123" },
        body: {
          error: {
            message: "Sensitive provider detail that must not be persisted",
            type: "image_generation_user_error",
            code: "content_policy_violation",
            category: "violence"
          }
        }.to_json
      )
    assessment = Assessment.new(prompt: "Fight scene", generation_model: "dall-e-3", photo: nil)

    error = assert_raises(CharacterImageGeneration::Refused) do
      CharacterImageGeneration.call(assessment)
    end

    assert_equal "The image service declined this request because it detected violence.", error.public_reason
    assert_equal(
      {
        "code" => "content_policy_violation",
        "request_id" => "req_refused_123",
        "category" => "violence"
      },
      error.metadata
    )
    assert_not_includes error.metadata.to_s, "Sensitive provider detail"
    assert_requested request, times: 1
  end

  test "uses a generic public reason when a moderation refusal reports only an unknown category" do
    stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: {
          error: {
            code: "moderation_blocked",
            moderation_details: { categories: [ "other" ] }
          }
        }.to_json
      )
    assessment = Assessment.new(prompt: "A character", generation_model: "dall-e-3", photo: nil)

    error = assert_raises(CharacterImageGeneration::Refused) do
      CharacterImageGeneration.call(assessment)
    end

    assert_equal "The image service declined this request without a more specific reason.", error.public_reason
    assert_equal({ "code" => "moderation_blocked", "category" => "other" }, error.metadata)
  end

  test "recognizes the documented content filter refusal code" do
    stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: { error: { code: "content_filter" } }.to_json
      )
    assessment = Assessment.new(prompt: "A character", generation_model: "dall-e-3", photo: nil)

    error = assert_raises(CharacterImageGeneration::Refused) do
      CharacterImageGeneration.call(assessment)
    end

    assert_equal "The image service declined this request without a more specific reason.", error.public_reason
    assert_equal({ "code" => "content_filter" }, error.metadata)
  end

  test "rethrows non-moderation provider errors without retrying" do
    request = stub_request(:post, "https://api.openai.com/v1/images/generations")
      .to_return(
        status: 400,
        headers: { "Content-Type" => "application/json" },
        body: { error: { code: "invalid_request_error" } }.to_json
      )
    assessment = Assessment.new(prompt: "A character", generation_model: "dall-e-3", photo: nil)

    assert_raises(Faraday::BadRequestError) do
      CharacterImageGeneration.call(assessment)
    end

    assert_requested request, times: 1
  end

  test "does not retry an uncertain provider timeout" do
    request = stub_request(:post, "https://api.openai.com/v1/images/generations").to_timeout
    assessment = Assessment.new(prompt: "A character", generation_model: "dall-e-3", photo: nil)

    assert_raises(Faraday::ConnectionFailed) do
      CharacterImageGeneration.call(assessment)
    end

    assert_requested request, times: 1
  end
end
