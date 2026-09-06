# frozen_string_literal: true

require "test_helper"

class BooksPagePartialTest < ActionView::TestCase
  test "renders a page's story text and one-based page number" do
    page = Page.new(book: books(:one), text: "The fox found the hidden door.")

    render partial: "books/page", locals: { page: page, index: 2 }

    assert_select ".story-body", "The fox found the hidden door."
    assert_select ".page-footer", "3"
  end
end
