# frozen_string_literal: true

require "test_helper"
require "pdf/reader"

class Lulu::BookletPdfTest < ActiveSupport::TestCase
  setup do
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Månen και το δάσος", total_pages: 1, language: "el",
      generation_status: :completed)
    page = book.pages.create!(text: "Godnat, κόσμε. En lille historie.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moonlit forest")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") do |file|
      illustration.original_image = file
    end
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
  end

  test "renders the retained edition as Lulu booklet PDFs" do
    assert defined?(Lulu::BookletPdf), "expected the booklet PDF renderer to exist"

    result = Lulu::BookletPdf.new(@order).render

    assert result.interior.start_with?("%PDF-")
    assert result.cover.start_with?("%PDF-")
    assert_equal 4, result.page_count
    assert_equal 1, result.blank_page_count

    interior = PDF::Reader.new(StringIO.new(result.interior))
    cover = PDF::Reader.new(StringIO.new(result.cover))
    assert_equal 4, interior.page_count
    assert_in_delta 5.25 * 72, interior.pages.first.width, 0.01
    assert_in_delta 8.25 * 72, interior.pages.first.height, 0.01
    assert_in_delta 10.25 * 72, cover.pages.first.width, 0.01
    assert_in_delta 8.25 * 72, cover.pages.first.height, 0.01
    assert_includes interior.pages.map(&:text).join(" "), "Godnat, κόσμε. En lille historie."
    assert_predicate interior.pages.second.xobjects, :any?
    assert_predicate cover.pages.first.xobjects, :any?
  end

  test "paginates long retained text without clipping its ending" do
    ending = "SLUTMARKØR τέλος"
    @order.print_order_pages.first.update!(text: ([ "En lang fortælling με λέξεις." ] * 450).join(" ") + " #{ending}")

    result = Lulu::BookletPdf.new(@order).render
    text = PDF::Reader.new(StringIO.new(result.interior)).pages.map(&:text).join(" ")

    assert_includes text, ending
    assert_equal 0, result.page_count % 4
    assert_operator result.page_count, :<=, 48
  end

  test "rejects a retained edition that exceeds the saddle-stitch limit" do
    source_blob = @order.print_order_pages.first.image.blob
    2.upto(47) do |position|
      page = @order.print_order_pages.create!(position:, text: "Story page #{position}")
      page.image.attach(source_blob)
    end

    assert_raises(Lulu::BookletPdf::PageLimitExceeded) do
      Lulu::BookletPdf.new(@order).render
    end
  end
end
