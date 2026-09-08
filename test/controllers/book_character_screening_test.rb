require "test_helper"

class BookCharacterScreeningControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.update!(tier: "free")
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "book creation cannot submit a held character" do
    character = characters(:hernandes)
    CharacterImageRequest.submit!(character)
    assert_no_enqueued_jobs only: GenerateBookJob do
      post books_url, params: { book: { name: "Held", total_pages: 1, character_ids: [ character.id ] } }
    end
    assert_response :unprocessable_content
  end

  test "new book cannot load another owner's character" do
    other = users(:two).characters.create!(name: "Private child")
    get new_book_url, params: { character_ids: [ other.id ] }
    assert_response :unprocessable_content
    assert_not_includes response.body, "Private child"
  end

  test "selection cannot attach a held character" do
    character = characters(:hernandes)
    CharacterImageRequest.submit!(character)
    post save_selected_characters_url, params: { book_id: books(:one).id, character_ids: [ character.id ] }
    assert_response :unprocessable_content
  end
end
