# frozen_string_literal: true

require "test_helper"

class BookCategorizationTest < ActiveSupport::TestCase
  test "classifies a completed book from its saved story" do
    book = completed_book_with_story("Mira sailed across the sea with a friendly dragon.")
    request = nil
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      request = parameters
      { "choices" => [ { "message" => { "content" => { categories: [ "Adventure", "Dragons" ] }.to_json } } ] }
    end

    BookCategorization.call(book, generation_attempt: book.generation_attempt, client: client)

    assert_equal [ "Adventure", "Dragons" ], book.reload.categories
    input = JSON.parse(request.fetch(:messages).last.fetch(:content))
    assert_equal [ "Mira sailed across the sea with a friendly dragon." ], input.fetch("story")
    assert_includes input.fetch("allowed_categories"), "Adventure"
    assert_equal "gpt-4.1-mini", request.fetch(:model)
    assert_equal({ type: "json_object" }, request.fetch(:response_format))
  end

  test "rejects categories outside the catalog" do
    book = completed_book_with_story("Mira explored the forest.")
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      { "choices" => [ { "message" => { "content" => { categories: [ "Invented" ] }.to_json } } ] }
    end

    assert_raises(BookCategorization::InvalidResponse) do
      BookCategorization.call(book, generation_attempt: book.generation_attempt, client: client)
    end
    assert_empty book.reload.categories
  end

  test "does not save a response from an obsolete generation attempt" do
    book = completed_book_with_story("Mira explored the forest.")
    original_attempt = book.generation_attempt
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      book.update_columns(generation_attempt: original_attempt + 1,
        generation_status: Book.generation_statuses.fetch("in_progress"))
      { "choices" => [ { "message" => { "content" => { categories: [ "Adventure" ] }.to_json } } ] }
    end

    result = BookCategorization.call(book, generation_attempt: original_attempt, client: client)

    assert_equal false, result
    assert_empty book.reload.categories
  end
  test "preserves categories assigned while classification is in flight" do
    book = completed_book_with_story("Mira explored the forest.")
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      book.update_columns(categories: [ "Friendship" ])
      { "choices" => [ { "message" => { "content" => { categories: [ "Adventure" ] }.to_json } } ] }
    end

    BookCategorization.call(book, generation_attempt: book.generation_attempt, client: client)

    assert_equal [ "Friendship" ], book.reload.categories
  end


  private

  def completed_book_with_story(text)
    book = Book.create!(user: users(:one), name: "Classified tale", total_pages: 1)
    book.update_columns(generation_status: Book.generation_statuses.fetch("completed"))
    book.pages.create!(text: text, generation_attempt: book.generation_attempt)
    book
  end
end
