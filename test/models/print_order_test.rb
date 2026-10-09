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
    @book.update_column(:book_font, "eb_garamond")
    order = nil
    assert defined?(PrintOrder), "expected the physical-order model to exist"

    order = PrintOrder.start_for!(user: @admin, book: @book)

    assert_equal "The retained adventure", order.title
    assert_equal "en", order.language
    assert_equal "eb_garamond", order.book_font
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

  test "changing the delivery address invalidates shipping and quote without invalidating PDFs" do
    order = PrintOrder.start_for!(user: @admin, book: @book)
    order.update!(
      recipient_name: "A Reader", street1: "Old Road 1", city: "Copenhagen", postcode: "2100",
      country_code: "DK", recipient_email: "reader@example.com", phone_number: "+45 12345678",
      shipping_option: "MAIL", shipping_options: [ { "level" => "MAIL" } ],
      quote: { "total_cost_incl_tax" => "12.00" }, quote_revision: order.checkout_revision,
      validation_state: "validated", validation_details: { "interior_id" => 1 }
    )
    original_content_revision = order.content_revision
    original_checkout_revision = order.checkout_revision

    assert order.save_delivery_address(street1: "New Road 2")

    order.reload
    assert_equal original_content_revision, order.content_revision
    assert_equal original_checkout_revision + 1, order.checkout_revision
    assert_nil order.shipping_option
    assert_empty order.shipping_options
    assert_empty order.quote
    assert_equal "not_started", order.validation_state
    assert_empty order.validation_details
  end

  test "delivery details become read only after submission starts" do
    order = PrintOrder.start_for!(user: @admin, book: @book)
    order.update!(
      recipient_name: "A Reader", street1: "Old Road 1", city: "Copenhagen", postcode: "2100",
      country_code: "DK", recipient_email: "reader@example.com", phone_number: "+45 12345678",
      submission_uuid: SecureRandom.uuid, workflow_state: "submitting"
    )

    refute order.save_delivery_address(street1: "Changed Road 2")

    assert_predicate order.errors[:base], :present?
    assert_equal "Old Road 1", order.reload.street1
  end

  test "a confirmed rejection can be reopened with a fresh checkout and preserved audit history" do
    order = PrintOrder.start_for!(user: @admin, book: @book)
    external_id = SecureRandom.uuid
    order.update!(
      workflow_state: "submission_failed",
      submission_uuid: external_id,
      submission_attempted_at: 1.minute.ago,
      submission_attempts: [ { "external_id" => external_id, "outcome" => "rejected" } ],
      validation_state: "validated",
      validation_details: { "content_revision" => 1, "checkout_revision" => 1 },
      shipping_option: "MAIL",
      quote: { "currency" => "EUR", "total_cost_incl_tax" => "14.80" },
      quote_revision: 1,
      failure_message: "Rejected"
    )
    previous_checkout_revision = order.checkout_revision

    assert order.retry_submission!

    order.reload
    assert_nil order.submission_uuid
    assert_nil order.submission_attempted_at
    assert_equal previous_checkout_revision + 1, order.checkout_revision
    assert_equal "not_started", order.validation_state
    assert_empty order.quote
    assert_equal external_id, order.submission_attempts.last.fetch("external_id")
    assert_equal "rejected", order.submission_attempts.last.fetch("outcome")
  end

  test "a failed state without a matching rejected attempt cannot clear its submission identifier" do
    order = PrintOrder.start_for!(user: @admin, book: @book)
    external_id = SecureRandom.uuid
    order.update!(
      workflow_state: "submission_failed",
      submission_uuid: external_id,
      submission_attempted_at: 1.minute.ago,
      submission_attempts: [ { "external_id" => "another-id", "outcome" => "rejected" } ]
    )

    refute order.retry_submission!

    assert_equal external_id, order.reload.submission_uuid
  end
end
