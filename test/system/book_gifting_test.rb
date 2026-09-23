# frozen_string_literal: true

require "application_system_test_case"
require "warden/test/helpers"

class BookGiftingTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    @user = User.create!(email: "gift-layout@gmail.com", name: "Alex", tier: "basic", language: "en")
    @user.create_tutorial!(terms: true)
    @book = @user.books.create!(name: "The Giftable Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    purchase = @user.book_purchases.create!(status: "paid", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, stripe_checkout_session_id: "cs_layout_#{SecureRandom.hex(6)}",
      stripe_payment_intent_id: "pi_layout_#{SecureRandom.hex(6)}", stripe_customer_id: "cus_layout",
      amount_total: 2500, currency: "dkk", paid_at: Time.current)
    credit = @user.book_credits.create!(book_purchase: purchase, status: "consumed")
    @user.book_credit_reservations.create!(book: @book, book_credit: credit, status: "consumed",
      consumed_at: Time.current)
    login_as @user, scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "gift action follows Read and the create card grows with the book card" do
    visit books_url

    assert_button "Send as gift"
    assert_equal_card_heights
    assert_operator element_edge(".library-read", "bottom"), :<,
      element_edge(".library-gift-action", "top")

    page.current_window.resize_to(390, 900)

    assert_equal_card_heights
  end

  test "trial book gift action opens the responsive purchase explanation in a modal" do
    @user.update!(tier: "free")
    legacy_book = @user.books.create!(name: "Legacy Trial Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    visit books_url

    within("article.library-book", text: legacy_book.name) do
      click_button "Send as gift"
    end

    assert_current_path books_path
    assert_selector "dialog[open]"
    assert_text 'Buy the book "Legacy Trial Adventure" to send it as a gift'
    assert_button "Buy the book"
    assert_button "Cancel"

    page.current_window.resize_to(390, 900)

    page_width = page.evaluate_script("document.documentElement.clientWidth")
    content_width = page.evaluate_script("document.documentElement.scrollWidth")
    assert_operator content_width, :<=, page_width + 1
  end

  test "available credit confirmation uses the modal and continues to the giftcard" do
    trial_book = @user.books.create!(name: "Credit Trial Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    reservation = @user.trial_book_reservations.create!(book: trial_book)
    credit = create_available_credit
    visit books_url

    within("article.library-book", text: trial_book.name) do
      click_button "Send as gift"
    end

    assert_current_path books_path
    assert_selector "dialog[open]"
    assert_text "Use one book credit?"
    click_button "Use credit and continue"

    assert_current_path new_book_book_gift_path(trial_book)
    assert_equal "consumed", credit.reload.status
    assert_equal "released", reservation.reload.status
  end

  private

  def assert_equal_card_heights
    create_height = element_edge(".library-create", "height")
    book_height = element_edge(".library-book", "height")
    assert_in_delta book_height, create_height, 1
  end

  def element_edge(selector, edge)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect()[#{edge.to_json}]")
  end

  def create_available_credit
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_modal_#{SecureRandom.hex(6)}",
      payment_intent_id: "pi_modal_#{SecureRandom.hex(6)}", stripe_customer_id: "cus_modal",
      price_id: "price_test", amount_total: 2500, currency: "dkk")
    purchase.book_credit
  end
end
