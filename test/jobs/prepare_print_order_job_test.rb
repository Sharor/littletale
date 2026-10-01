# frozen_string_literal: true

require "test_helper"
require "pdf/reader"

class PreparePrintOrderJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Prepared moon", total_pages: 1, language: "da",
      generation_status: :completed)
    page = book.pages.create!(text: "En trykt historie.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A printed moon")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") do |file|
      illustration.original_image = file
    end
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
  end

  test "stores PDFs and page metadata for the requested content revision" do
    assert defined?(PreparePrintOrderJob), "expected an asynchronous print preparation job"

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)

    @order.reload
    assert_predicate @order.interior_pdf, :attached?
    assert_predicate @order.cover_pdf, :attached?
    assert_equal @order.content_revision, @order.artifacts_revision
    assert_equal 4, @order.interior_page_count
    assert_equal 1, @order.blank_page_count
    assert_equal "prepared", @order.workflow_state
    assert_equal 4, PDF::Reader.new(StringIO.new(@order.interior_pdf.download)).page_count
  end

  test "does not attach artifacts for a stale revision" do
    assert defined?(PreparePrintOrderJob), "expected an asynchronous print preparation job"

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision + 1)

    @order.reload
    assert_not @order.interior_pdf.attached?
    assert_not @order.cover_pdf.attached?
    assert_equal "draft", @order.workflow_state
  end
end
