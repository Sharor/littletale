# frozen_string_literal: true

require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "requires a book" do
    page = Page.new(text: "A small adventure")

    assert_not page.valid?
    assert_includes page.errors[:book], "must exist"
  end

  test "belongs to a book and removes its illustration when deleted" do
    book = Book.create!(user: users(:one), name: "A small adventure", total_pages: 1)
    page = book.pages.create!(text: "A small adventure")
    illustration = Illustration.create!(page: page, original_description: "A castle")

    assert_equal book, page.book
    assert_difference("Illustration.count", -1) { page.destroy! }
    assert_not Illustration.exists?(illustration.id)
  end
end
