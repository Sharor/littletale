# frozen_string_literal: true

require "test_helper"

class BookTest < ActiveSupport::TestCase
  test "pending book immediately displays an accessible preparation status" do
    book = Book.new(user: users(:one), name: "New tale", total_pages: 1, generation_status: :pending)

    html = ApplicationController.render(partial: "books/book_state", locals: { book: book })
    fragment = Nokogiri::HTML.fragment(html)

    assert_includes fragment.at_css('[role="status"]').to_s, "Getting your book ready"
    assert_includes html, "New tale"
    assert_includes html, "automatically"
  end

  test "failed book displays available pages and explains the incomplete generation" do
    book = books(:one)
    book.update_columns(generation_status: Book.generation_statuses.fetch("failed"), total_pages: 2,
      generation_failure: { "type" => "openai_image_moderation_blocked" })
    missing = book.pages.create!(text: "Missing illustration", generation_attempt: book.generation_attempt)
    Illustration.create!(page: missing)
    ready = book.pages.create!(text: "Available adventure", generation_attempt: book.generation_attempt)
    Illustration.create!(page: ready).update_column(:original_image, "available.png")

    html = ApplicationController.render(partial: "books/book_state", locals: { book: book })

    assert_includes html, "This book is incomplete"
    assert_includes html, "Available adventure"
    assert_includes html, "Missing illustration"
    assert_includes html, "Illustration unavailable"
    assert_includes html, "available.png"
  end

  test "completed book state renders story pages in a background update" do
    book = books(:one)
    book.update_columns(generation_status: Book.generation_statuses.fetch("completed"), total_pages: 1)
    page = book.pages.create!(text: "A newly finished adventure", generation_attempt: book.generation_attempt)
    illustration = Illustration.create!(page: page)
    illustration.update_column(:original_image, "finished.png")

    html = ApplicationController.render(partial: "books/book_state", locals: { book: book })

    assert_includes html, 'id="storybook"'
    assert_includes html, "A newly finished adventure"
    assert_includes html, "finished.png"
  end

  test "generating book state renders outside an authenticated request" do
    book = Book.new(user: users(:one), name: "New tale", total_pages: 1, generation_status: :in_progress)

    html = ApplicationController.render(partial: "books/book_state", locals: { book: book })

    assert_includes html, "castle_construction"
    assert_not_includes html, "Rerun generation"
  end

  test "requires a name and a positive page count" do
    book = Book.new(user: users(:one), total_pages: 0)

    assert_not book.valid?
    assert_includes book.errors[:name], "can't be blank"
    assert_includes book.errors[:total_pages], "must be greater than 0"
  end

  test "enforces the user's tier page limit" do
    user = users(:one)
    user.update!(tier: "free")
    book = Book.new(user: user, name: "Long tale", total_pages: 6)

    assert_not book.valid?
    assert_includes book.errors[:total_pages], "cannot exceed 5 pages for the Free tier"
  end

  test "maps completed page counts to construction levels" do
    book = Book.new(user: users(:one), name: "Tale", total_pages: 5)

    assert_equal 1, book.construction_level
  end
end
