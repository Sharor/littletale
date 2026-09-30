# frozen_string_literal: true

require "test_helper"

class PrintOrderTest < ActiveSupport::TestCase
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @book = @admin.books.create!(
      name: "The retained adventure",
      total_pages: 1,
      language: "en",
      generation_status: :completed
    )
    page = @book.pages.create!(text: "Once upon a snapshot.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moonlit forest")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") do |file|
      illustration.original_image = file
    end
    illustration.save!
  end

  test "starting an order retains the selected completed book" do
    order = nil
    assert defined?(PrintOrder), "expected the physical-order model to exist"

    order = PrintOrder.start_for!(user: @admin, book: @book)

    assert_equal "The retained adventure", order.title
    assert_equal "en", order.language
    assert_equal [ "Once upon a snapshot." ], order.print_order_pages.pluck(:text)
    assert_predicate order.print_order_pages.first.image, :attached?
  end

  test "an incomplete book cannot be ordered" do
    @book.update_columns(generation_status: Book.generation_statuses.fetch("in_progress"))

    assert_no_difference([ "PrintOrder.count", "PrintOrderPage.count" ]) do
      assert_raises(PrintOrder::IneligibleBook) do
        PrintOrder.start_for!(user: @admin, book: @book)
      end
    end
  end

  test "another user's book cannot be ordered" do
    assert_no_difference([ "PrintOrder.count", "PrintOrderPage.count" ]) do
      assert_raises(PrintOrder::IneligibleBook) do
        PrintOrder.start_for!(user: users(:two), book: @book)
      end
    end
  end

  test "a book with a missing illustration cannot be ordered" do
    @book.current_pages.first.illustration.remove_original_image!

    assert_no_difference([ "PrintOrder.count", "PrintOrderPage.count" ]) do
      assert_raises(PrintOrder::IneligibleBook) do
        PrintOrder.start_for!(user: @admin, book: @book)
      end
    end
  end

  test "the retained edition survives source edits and deletion" do
    order = PrintOrder.start_for!(user: @admin, book: @book)
    source_page = @book.current_pages.first

    source_page.update!(text: "A rewritten source story.")
    @book.destroy!

    assert_nil order.reload.source_book
    assert_equal [ "Once upon a snapshot." ], order.print_order_pages.pluck(:text)
    assert_predicate order.print_order_pages.first.image, :attached?
  end
end
