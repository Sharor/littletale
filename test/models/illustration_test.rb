# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class IllustrationTest < ActiveSupport::TestCase
  test "page image request constrains repeated actions to one depiction of each character" do
    received = nil
    images = Object.new
    images.define_singleton_method(:edit) do |parameters:|
      received = parameters
      { "data" => [] }
    end
    illustration = Illustration.new(original_description:
      "David, Amalia, and Olivia share a picnic. David holds up a phone for a family selfie.")

    illustration.stub :client, Struct.new(:images).new(images) do
      illustration.gpt_image_1_edit([])
    end

    prompt = received.fetch(:prompt)
    assert_includes prompt, illustration.original_description
    assert_includes prompt, "one scene at a single moment"
    assert_includes prompt, "each character present exactly once"
    assert_includes prompt, "Do not repeat characters"
    assert_includes prompt, "phone screens"
    assert_includes prompt, "identity references, not additional people"
  end

  test "book image provider calls do not silently retry uncertain failures" do
    calls = 0
    images = Object.new
    images.define_singleton_method(:edit) do |parameters:|
      calls += 1
      raise Timeout::Error, "uncertain response"
    end
    illustration = Illustration.new(original_description: "A park")
    illustration.stub :client, Struct.new(:images).new(images) do
      assert_raises(Timeout::Error) { illustration.gpt_image_1_edit([]) }
    end
    assert_equal 1, calls
  end

  test "builds a single-character prompt with the supplied description" do
    illustration = Illustration.new

    prompt = illustration.build_prompt

    assert_includes prompt, "plaintext"
    assert_includes prompt, illustration.style_and_resolution
  end

  test "includes the stored description in book-image specifications" do
    illustration = Illustration.new(original_description: "A castle under the moon")

    assert_includes illustration.specifications, "A castle under the moon"
  end

  test "sends the expected request to the image client" do
    response = { "data" => [ { "url" => "https://images.example.test/generated.png" } ] }
    received_parameters = nil
    images = Object.new
    images.define_singleton_method(:generate) do |parameters:|
      received_parameters = parameters
      response
    end

    illustration = Illustration.new
    illustration.stub :client, Struct.new(:images).new(images) do
      assert_equal response, illustration.dalle_response("Draw a fox")
    end

    assert_equal "Draw a fox", received_parameters[:prompt]
    assert_equal "dall-e-3", received_parameters[:model]
    assert_equal "1024x1024", received_parameters[:size]
    assert_equal 1, received_parameters[:n]
  end

  test "records a moderation block with enough context for admin investigation" do
    book = Book.create!(user: users(:one), name: "Blocked story", plot: "A park adventure", total_pages: 1)
    character = Character.create!(user: users(:one), name: "Reference character")
    reference = Illustration.create!(character: character, original_description: "Reference image")
    book.characters << character
    page = book.pages.create!(text: "The characters celebrate in the park.")
    illustration = Illustration.create!(page: page, original_description: "A celebration in the park")
    error = Faraday::BadRequestError.new(
      "blocked",
      status: 400,
      headers: { "x-request-id" => "req_blocked" },
      body: {
        "error" => {
          "message" => "Rejected by the safety system",
          "code" => "moderation_blocked",
          "moderation_details" => { "moderation_stage" => "output", "categories" => [ "other" ] }
        }
      }
    )

    assert_nil illustration.send(:record_moderation_failure!, error, [ character ])

    assert_predicate book.reload, :failed?
    assert_equal "openai_image_moderation_blocked", book.generation_failure.fetch("type")
    assert_equal "trial", book.generation_failure.fetch("account_access")
    assert_equal illustration.id, book.generation_failure.fetch("illustration_id")
    assert_equal "req_blocked", illustration.reload.generation_metadata.dig("failure", "request_id")
    assert_equal "gpt-image-1", illustration.generation_metadata.dig("request", "model")
    assert_equal [ character.id ], illustration.generation_metadata.dig("request", "character_ids")
    assert_equal reference.id, illustration.generation_metadata.dig("request", "reference_images", 0, "illustration_id")
    assert_equal "gpt-image-1", book.generation_failure.dig("request", "model")
  end
end
