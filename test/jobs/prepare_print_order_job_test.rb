# frozen_string_literal: true

require "test_helper"
require "pdf/reader"
require "minitest/mock"

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

  test "records an expected rendering failure and leaves preparation retryable" do
    renderer = Object.new
    renderer.define_singleton_method(:render) do
      raise Lulu::BookletPdf::RenderingError, "corrupt retained image"
    end

    Lulu::BookletPdf.stub(:new, renderer) do
      PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
    end

    @order.reload
    assert_equal "failed", @order.workflow_state
    assert_match(/could not be built/i, @order.failure_message)
    assert_not @order.interior_pdf.attached?
    assert @order.editable?
  end

  test "does not persist rendered files after submission starts during rendering" do
    order = @order
    renderer = Object.new
    renderer.define_singleton_method(:render) do
      order.update!(workflow_state: "submitting", submission_uuid: SecureRandom.uuid)
      Lulu::BookletPdf::Result.new(interior: "%PDF-interior", cover: "%PDF-cover", page_count: 4,
        blank_page_count: 1)
    end

    Lulu::BookletPdf.stub(:new, renderer) do
      PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
    end

    @order.reload
    assert_equal "submitting", @order.workflow_state
    assert_not @order.interior_pdf.attached?
    assert_not @order.cover_pdf.attached?
  end

  test "records a corrupt retained JPEG as a retryable preparation failure" do
    replace_retained_image("\xFF\xD8\xFF\xE0\x00\x02\x00\x00\x00\x02".b, "corrupt.jpg", "image/jpeg")
    @order.update!(workflow_state: "preparing")

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)

    assert_equal "failed", @order.reload.workflow_state
    assert_match(/could not be built/i, @order.failure_message)
  end

  test "records corrupt retained PNG data as a retryable preparation failure" do
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + ("\0" * 4) }
    png = "\x89PNG\r\n\x1A\n".b
    png << chunk.call("IHDR", [ 1, 1, 8, 2, 0, 0, 0 ].pack("NNCCCCC"))
    png << chunk.call("IDAT", "bad")
    png << chunk.call("IEND", "")
    replace_retained_image(png, "corrupt.png", "image/png")
    @order.update!(workflow_state: "preparing")

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)

    assert_equal "failed", @order.reload.workflow_state
    assert_match(/could not be built/i, @order.failure_message)
  end

  test "records a truncated retained JPEG as a retryable preparation failure" do
    replace_retained_image("\xFF\xD8\xFF".b, "truncated.jpg", "image/jpeg")
    @order.update!(workflow_state: "preparing")

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)

    assert_equal "failed", @order.reload.workflow_state
    assert_match(/could not be built/i, @order.failure_message)
  end

  test "records a retained JPEG with unsupported channels as a retryable preparation failure" do
    jpeg = "\xFF\xD8\xFF\xC0\x00\x08".b + [ 8, 1, 1, 2 ].pack("CnnC")
    replace_retained_image(jpeg, "unsupported-channels.jpg", "image/jpeg")
    @order.update!(workflow_state: "preparing")

    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)

    assert_equal "failed", @order.reload.workflow_state
    assert_match(/could not be built/i, @order.failure_message)
  end

  private

  def replace_retained_image(contents, filename, content_type)
    @order.print_order_pages.first.image.attach(io: StringIO.new(contents), filename:, content_type:)
  end
end
