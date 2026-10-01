# frozen_string_literal: true

require "application_system_test_case"
require "warden/test/helpers"

class PrintOrdersTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    @admin = users(:one)
    @admin.update!(admin: true)
    @admin.tutorial.update!(terms: true)
    @book = @admin.books.create!(name: "The browser moon", total_pages: 1, language: "en",
      generation_status: :completed)
    story_page = @book.pages.create!(text: "The moon followed the reader home.", story_position: 1)
    illustration = story_page.create_illustration!(original_description: "A moon above a storybook")
    File.open(file_fixture("character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    login_as @admin, scope: :user
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
    Warden.test_reset!
  end

  test "admin chooses, reads, returns, and completes the three-step order flow" do
    page.current_window.resize_to(1400, 1000)
    visit print_orders_url
    click_link "Start a book order"

    choose "book_id_#{@book.id}"
    click_button "Save selected book"
    assert_text @book.name

    click_link "Read retained book"
    turn_reader_page
    assert_text "The moon followed the reader home."
    turn_reader_page
    click_link "Back to order"
    assert_text @book.name

    click_link "Continue to delivery"
    fill_in "Recipient name", with: "A Reader"
    fill_in "Address line 1", with: "Story Lane 4"
    fill_in "City", with: "Copenhagen"
    fill_in "Postal code", with: "2100"
    fill_in "Country code", with: "DK"
    fill_in "Recipient email", with: "reader@example.com"
    fill_in "Phone number", with: "+45 12345678"
    click_button "Continue to print options"

    assert_text "Choose print format"
    assert_text "Premium color booklet"
    assert_button "Build print preview"
    page.save_screenshot(Rails.root.join("tmp/screenshots/print-orders-desktop.png"))

    page.current_window.resize_to(390, 900)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert_selector "header a[aria-label='Orders']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/print-orders-phone.png"))
  end

  test "disabled orders disappear and cannot render for an admin" do
    ENV["LULU_ORDERS_ENABLED"] = "false"

    visit books_url
    assert_no_link "Orders"

    visit print_orders_url
    assert_no_text "Book orders"
  end

  private

  def turn_reader_page
    assert_selector "#nextPage", visible: :all
    page.execute_script('document.getElementById("nextPage").click()')
  end
end
