# frozen_string_literal: true

require "test_helper"
require "base64"
require "webmock/minitest"

class BookWardrobeImageGenerationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  Outfit = Data.define(:description, :character_snapshot, :source_image, :book)
  Source = Data.define(:download)
  Book = Data.define(:art_style_prompt)

  setup { VCR.turn_off!(ignore_cassettes: true) }
  teardown { VCR.turn_on! }

  test "edits the approved illustration with identity and exact wardrobe instructions" do
    request = stub_request(:post, "https://api.openai.com/v1/images/edits")
      .with do |request|
        body = request.body
        [ "gpt-image-1", "1024x1024", "yellow raincoat and green boots", "Ava", "7", "curly", "neutral background", "age-appropriate swimwear", "full character", "same character", "\x89PNG".b ].all? { |part| body.include?(part) }
      end.to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: "req_outfit", data: [ { b64_json: Base64.strict_encode64(png) } ] }.to_json)

    result = BookWardrobeImageGeneration.call(outfit)

    assert_equal png, result.fetch(:io).read
    assert_equal Encoding::BINARY, result.fetch(:io).external_encoding
    assert_equal "outfit.png", result.fetch(:filename)
    assert_equal "image/png", result.fetch(:content_type)
    assert_equal "req_outfit", result.fetch(:request_id)
    assert_requested request, times: 1
  end

  test "converts explicit rejection to sanitized refusal without provider prose" do
    request = stub_request(:post, "https://api.openai.com/v1/images/edits").to_return(status: 400,
      headers: { "Content-Type" => "application/json", "x-request-id" => "req_refused" },
      body: { error: { code: "moderation_blocked", message: "Private provider detail", category: "<script>private</script>" } }.to_json)

    error = assert_raises(BookWardrobeImageGeneration::Refused) { BookWardrobeImageGeneration.call(outfit) }
    assert_equal "The image service declined this outfit request.", error.public_reason
    assert_equal({ "code" => "moderation_blocked", "request_id" => "req_refused" }, error.metadata)
    assert_requested request, times: 1
  end

  test "wardrobe image requests carry the saved roles and appearance metadata" do
    saved_outfit = Outfit.new(description: "yellow raincoat and green boots", source_image: Source.new(download: png),
      character_snapshot: { "name" => "Ava", "age" => 7, "gender" => "Girl", "eye_color" => "Green",
        "ethnicity" => "Asian", "roles" => [ "Younger sibling", "Freckles", "Supporting" ] },
      book: Book.new(BookArtStyle.fetch("western_book_style").prompt))
    body = nil
    stub_request(:post, "https://api.openai.com/v1/images/edits").to_return do |request|
      body = request.body
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: [ { b64_json: Base64.strict_encode64(png) } ] }.to_json }
    end

    BookWardrobeImageGeneration.call(saved_outfit)

    assert_includes body, '"roles":["Younger sibling","Freckles","Supporting"]'
    assert_includes body, '"eye_color":"Green"'
    assert_includes body, '"ethnicity":"Asian"'
  end

  test "restyles wardrobe references to the book's selected art style" do
    body = nil
    styled_outfit = Outfit.new(description: "yellow raincoat and green boots", source_image: Source.new(download: png),
      character_snapshot: { "name" => "Ava", "age" => 7 },
      book: Book.new(BookArtStyle.fetch("cut_paper_collage").prompt))
    stub_request(:post, "https://api.openai.com/v1/images/edits").to_return do |request|
      body = request.body
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { data: [ { b64_json: Base64.strict_encode64(png) } ] }.to_json }
    end

    BookWardrobeImageGeneration.call(styled_outfit)

    assert_includes body, "Cut-paper collage"
    assert_includes body, "tactile fibers"
    assert_includes body, "Restyle the character"
  end

  test "propagates timeout without retry" do
    request = stub_request(:post, "https://api.openai.com/v1/images/edits").to_timeout
    assert_raises(Faraday::ConnectionFailed) { BookWardrobeImageGeneration.call(outfit) }
    assert_requested request, times: 1
  end

  test "rejects unreadable provider image bytes" do
    stub_request(:post, "https://api.openai.com/v1/images/edits").to_return(status: 200,
      headers: { "Content-Type" => "application/json" }, body: { data: [ { b64_json: Base64.strict_encode64("not an image") } ] }.to_json)
    assert_raises(BookWardrobeImageGeneration::InvalidImage) { BookWardrobeImageGeneration.call(outfit) }
  end

  private

  def png
    @png ||= begin
      image = MiniMagick::Image.read(Base64.strict_decode64("R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
      image.format("png")
      image.to_blob
    ensure
      image&.destroy!
    end
  end

  def outfit
    Outfit.new(description: "yellow raincoat and green boots", character_snapshot: { "name" => "Ava", "age" => 7, "gender" => "girl", "hair_color" => "brown", "hair_style" => "curly" }, source_image: Source.new(download: png),
      book: Book.new(BookArtStyle.fetch("western_book_style").prompt))
  end
end
