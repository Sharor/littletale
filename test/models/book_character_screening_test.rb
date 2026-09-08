require "test_helper"
require "minitest/mock"

class BookCharacterScreeningTest < ActiveSupport::TestCase
  test "review blocks dependent book work but not an unrelated book" do
    character = characters(:hernandes)
    request = CharacterImageRequest.submit!(character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private")
    book = books(:one)
    assert_not book.characters_ready_for_generation?
    assert Book.new(user: character.user, name: "Other", total_pages: 1).characters_ready_for_generation?
    job = GenerateBookJob.new
    job.stub :initialize_AI, ->(*) { flunk "held character must stop paid story work" } do
      job.perform(book.id)
    end
    assert_equal "character_image_not_ready", book.reload.generation_failure["type"]
  end

  test "legacy completed images remain usable but new incomplete images do not" do
    character = characters(:hernandes)
    character.update!(generation_status: :completed)
    character.illustration.update!(original_image: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/character.png"), "image/png"))
    assert character.reload.image_ready_for_book?
    request = CharacterImageRequest.submit!(character)
    request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    assert_not character.reload.image_ready_for_book?
  end

  test "book eligibility rejects another owner's character" do
    character = characters(:hernandes)
    character.update!(generation_status: :completed)
    character.illustration.update!(original_image: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/character.png"), "image/png"))
    book = Book.new(user: users(:two), name: "Wrong owner", total_pages: 1, characters: [ character ])
    assert_not book.characters_ready_for_generation?
  end

  test "page work stops if character becomes unapproved after book work started" do
    book = books(:one)
    request = CharacterImageRequest.submit!(characters(:hernandes))
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private")
    assert_no_difference "Page.count" do
      GeneratePageJob.perform_now(book.id, { "story" => "A ride", "image" => "A bike" })
    end
    assert_equal "character_image_not_ready", book.reload.generation_failure["type"]
  end
end
