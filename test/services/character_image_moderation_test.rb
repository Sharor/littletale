require "test_helper"
require "minitest/mock"

class CharacterImageModerationTest < ActiveSupport::TestCase
  Result = Struct.new(:prompt, :photo, keyword_init: true)
  Blob = Struct.new(:byte_size, :content_type, keyword_init: true)

  class Photo
    attr_reader :blob

    def initialize(bytes:, content_type:)
      @bytes = bytes
      @blob = Blob.new(byte_size: bytes.bytesize, content_type: content_type)
    end

    def attached?
      true
    end

    def download
      @bytes
    end
  end

  class OversizedPhoto < Photo
    def initialize
      @blob = Blob.new(byte_size: 20.megabytes + 1, content_type: "image/png")
    end

    def download
      raise "oversized photos must be rejected before download"
    end
  end

  CLEAR_RESPONSE = {
    "id" => "modr-clear-123",
    "model" => "omni-moderation-latest",
    "results" => [
      {
        "flagged" => false,
        "categories" => { "violence" => false, "sexual/minors" => false },
        "category_scores" => { "violence" => 0.001, "sexual/minors" => 0.0 },
        "category_applied_input_types" => {
          "violence" => [ "text", "image" ],
          "sexual/minors" => [ "text" ]
        }
      }
    ]
  }.freeze

  test "approves a clear text prompt and returns only sanitized evidence" do
    client = moderation_client_for(
      { model: "omni-moderation-latest", input: [ { type: "text", text: "A cheerful child explorer" } ] },
      CLEAR_RESPONSE
    )

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A cheerful child explorer", photo: nil))
    end

    assert_equal "approved", result.fetch(:outcome)
    assert_equal "moderation_clear", result.fetch(:internal_reason)
    assert_nil result.fetch(:public_reason)
    assert_equal(
      {
        "id" => "modr-clear-123",
        "model" => "omni-moderation-latest",
        "categories" => { "violence" => false, "sexual/minors" => false },
        "scores" => { "violence" => 0.001, "sexual/minors" => 0.0 },
        "applied_input_types" => {
          "violence" => [ "text", "image" ],
          "sexual/minors" => [ "text" ]
        }
      },
      result.fetch(:metadata)
    )
  end

  test "submits the exact prompt and a decodable photo to multimodal moderation" do
    bytes = one_pixel_png
    expected_input = [
      { type: "text", text: "Turn this person into a storybook character" },
      { type: "image_url", image_url: { url: "data:image/png;base64,#{Base64.strict_encode64(bytes)}" } }
    ]
    client = moderation_client_for(
      { model: "omni-moderation-latest", input: expected_input },
      CLEAR_RESPONSE
    )
    assessment = Result.new(
      prompt: "Turn this person into a storybook character",
      photo: Photo.new(bytes: bytes, content_type: "image/png")
    )

    result = with_openai_client(client) { CharacterImageModeration.call(assessment) }

    assert_equal "approved", result.fetch(:outcome)
    assert_not_includes result.fetch(:metadata).inspect, Base64.strict_encode64(bytes)
    assert_equal [ "text" ], result.dig(:metadata, "applied_input_types", "sexual/minors")
  end

  test "holds a flagged result for review without a public reason" do
    response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
    response["results"][0]["flagged"] = true
    response["results"][0]["categories"]["violence"] = true
    client = moderation_client_for(any_parameters, response)

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A battle scene", photo: nil))
    end

    assert_equal "needs_review", result.fetch(:outcome)
    assert_equal "moderation_flagged", result.fetch(:internal_reason)
    assert_nil result.fetch(:public_reason)
  end

  test "accepts equivalent moderation category hashes in different key orders" do
    response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
    response["results"][0]["category_scores"] = {
      "sexual/minors" => 0.0,
      "violence" => 0.001
    }
    client = moderation_client_for(any_parameters, response)

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
    end

    assert_equal "approved", result.fetch(:outcome)
  end

  test "holds a result with a true category even when the aggregate flag is false" do
    response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
    response["results"][0]["categories"]["violence"] = true
    client = moderation_client_for(any_parameters, response)

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
    end

    assert_equal "needs_review", result.fetch(:outcome)
    assert_equal "moderation_flagged", result.fetch(:internal_reason)
    assert_nil result.fetch(:public_reason)
  end

  test "holds non-finite and out-of-range category scores as malformed" do
    [ Float::NAN, Float::INFINITY, -0.01, 1.01 ].each do |invalid_score|
      response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
      response["results"][0]["category_scores"]["violence"] = invalid_score
      client = moderation_client_for(any_parameters, response)

      result = with_openai_client(client) do
        CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
      end

      assert_equal "needs_review", result.fetch(:outcome), "score: #{invalid_score.inspect}"
      assert_equal "moderation_response_malformed", result.fetch(:internal_reason)
    end
  end

  test "allows unsupported categories to have no applied input types" do
    response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
    response["results"][0]["category_applied_input_types"]["sexual/minors"] = []
    client = moderation_client_for(any_parameters, response)

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
    end

    assert_equal "approved", result.fetch(:outcome)
    assert_equal [], result.dig(:metadata, "applied_input_types", "sexual/minors")
  end

  test "handles the complete omni moderation category shape" do
    categories = {
      "harassment" => false,
      "harassment/threatening" => false,
      "hate" => false,
      "hate/threatening" => false,
      "illicit" => false,
      "illicit/violent" => false,
      "self-harm" => false,
      "self-harm/intent" => false,
      "self-harm/instructions" => false,
      "sexual" => false,
      "sexual/minors" => false,
      "violence" => false,
      "violence/graphic" => false
    }
    scores = categories.transform_values { 0.001 }
    input_types = categories.transform_values { [ "text" ] }
    input_types["self-harm"] = [ "text", "image" ]
    input_types["sexual"] = [ "text", "image" ]
    input_types["sexual/minors"] = [ "text" ]
    input_types["violence"] = [ "text", "image" ]
    input_types["violence/graphic"] = [ "text", "image" ]
    response = {
      "id" => "modr-complete-123",
      "model" => "omni-moderation-latest",
      "results" => [
        {
          "flagged" => false,
          "categories" => categories,
          "category_scores" => scores,
          "category_applied_input_types" => input_types
        }
      ]
    }
    client = moderation_client_for(any_parameters, response)
    assessment = Result.new(
      prompt: "Turn this person into a storybook character",
      photo: Photo.new(bytes: one_pixel_png, content_type: "image/png")
    )

    result = with_openai_client(client) { CharacterImageModeration.call(assessment) }

    assert_equal "approved", result.fetch(:outcome)
    assert_equal categories, result.dig(:metadata, "categories")
    assert_equal scores, result.dig(:metadata, "scores")
    assert_equal input_types, result.dig(:metadata, "applied_input_types")
  end

  test "holds malformed moderation evidence for review" do
    response = {
      "id" => "modr-incomplete",
      "model" => "omni-moderation-latest",
      "results" => [ { "flagged" => false, "categories" => {}, "category_scores" => {} } ]
    }
    client = moderation_client_for(any_parameters, response)

    result = with_openai_client(client) do
      CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
    end

    assert_equal "needs_review", result.fetch(:outcome)
    assert_equal "moderation_response_malformed", result.fetch(:internal_reason)
    assert_nil result.fetch(:public_reason)
    assert_equal(
      {
        "id" => "modr-incomplete",
        "model" => "omni-moderation-latest",
        "categories" => {},
        "scores" => {}
      },
      result.fetch(:metadata)
    )
  end

  test "does not approve a photo when the response only assessed text inputs" do
    response = Marshal.load(Marshal.dump(CLEAR_RESPONSE))
    response["results"][0]["category_applied_input_types"].transform_values! { [ "text" ] }
    client = moderation_client_for(any_parameters, response)
    assessment = Result.new(
      prompt: "Turn this person into a storybook character",
      photo: Photo.new(bytes: one_pixel_png, content_type: "image/png")
    )

    result = with_openai_client(client) { CharacterImageModeration.call(assessment) }

    assert_equal "needs_review", result.fetch(:outcome)
    assert_equal "moderation_image_not_assessed", result.fetch(:internal_reason)
    assert_nil result.fetch(:public_reason)
    assert_equal [ "text" ], result.dig(:metadata, "applied_input_types", "violence")
  end

  test "rejects unsupported declared image types before calling moderation" do
    assessment = Result.new(
      prompt: "A child reading",
      photo: Photo.new(bytes: one_pixel_png, content_type: "application/pdf")
    )

    result = without_openai_client { CharacterImageModeration.call(assessment) }

    assert_equal "rejected", result.fetch(:outcome)
    assert_equal "unsupported_image_type", result.fetch(:internal_reason)
    assert_match(/replace.*JPEG.*PNG.*WEBP.*GIF/i, result.fetch(:public_reason))
    assert_equal({}, result.fetch(:metadata))
  end

  test "rejects photos larger than twenty megabytes before downloading or moderating" do
    assessment = Result.new(prompt: "A child reading", photo: OversizedPhoto.new)

    result = without_openai_client { CharacterImageModeration.call(assessment) }

    assert_equal "rejected", result.fetch(:outcome)
    assert_equal "image_too_large", result.fetch(:internal_reason)
    assert_match(/replace.*20 MB/i, result.fetch(:public_reason))
  end

  test "rejects unreadable bytes even when the declared type is supported" do
    assessment = Result.new(
      prompt: "A child reading",
      photo: Photo.new(bytes: "not an image", content_type: "image/png")
    )

    result = without_openai_client { CharacterImageModeration.call(assessment) }

    assert_equal "rejected", result.fetch(:outcome)
    assert_equal "unreadable_image", result.fetch(:internal_reason)
    assert_match(/replace.*valid image/i, result.fetch(:public_reason))
  end

  test "lets transport failures escape for the screening job to retry" do
    client = Object.new
    client.define_singleton_method(:moderations) { |parameters:| raise Faraday::TimeoutError, parameters.inspect }

    error = assert_raises(Faraday::TimeoutError) do
      with_openai_client(client) do
        CharacterImageModeration.call(Result.new(prompt: "A child reading", photo: nil))
      end
    end

    assert_includes error.message, "omni-moderation-latest"
  end

  private

  def moderation_client_for(expected_parameters, response)
    Object.new.tap do |client|
      client.define_singleton_method(:moderations) do |parameters:|
        unless expected_parameters == :any || expected_parameters == parameters
          raise Minitest::Assertion, "Expected #{expected_parameters.inspect}, got #{parameters.inspect}"
        end

        response
      end
    end
  end

  def any_parameters
    :any
  end

  def with_openai_client(client, &block)
    OpenAI::Client.stub(:new, client, &block)
  end

  def without_openai_client(&block)
    OpenAI::Client.stub(:new, ->(*) { flunk "moderation client must not be created" }, &block)
  end

  def one_pixel_png
    Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )
  end
end
