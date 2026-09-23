# frozen_string_literal: true

require "test_helper"

class BookGiftRetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @sender = users(:one)
    @sender.update!(tier: "basic", admin: false, language: "en")
    @sender.tutorial.update!(terms: true)
    book = @sender.books.create!(name: "Paid Gift", total_pages: 1,
      generation_status: :completed, language: "en")
    book.pages.create!(text: "A retained page", story_position: 1)
    purchase = @sender.book_purchases.create!(status: "paid", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, stripe_checkout_session_id: "cs_retry",
      stripe_payment_intent_id: "pi_retry", stripe_customer_id: "cus_retry",
      amount_total: 2500, currency: "dkk", paid_at: Time.current)
    credit = @sender.book_credits.create!(book_purchase: purchase, status: "consumed")
    @sender.book_credit_reservations.create!(book: book, book_credit: credit, status: "consumed",
      consumed_at: Time.current)
    @gift = BookGift.issue!(source_book: book, sender: @sender, attributes: {
      recipient_name: "Reader", recipient_email: "reader@gmail.com", sender_callname: "Alex",
      message: "For you", language: "en"
    })
    @old_token = @gift.invitation_token
    @gift.update!(delivery_status: "failed", delivery_error: "Provider unavailable")
    sign_in @sender
  end

  test "sender sees failed delivery and a retry action" do
    get gift_invitation_url(@old_token)

    assert_response :success
    assert_select "[data-delivery-status='failed']", text: /Provider unavailable/
    assert_select "form[action='#{retry_delivery_book_gift_path(@gift)}']"
  end

  test "retry reuses the token and provider idempotency key" do
    @gift.update!(delivery_attempt_id: "stable-attempt")

    assert_enqueued_with(job: DeliverGiftEmailJob, args: [ @gift.id, "stable-attempt" ]) do
      post retry_delivery_book_gift_url(@gift)
    end

    assert_equal @gift, BookGift.find_by_invitation_token(@old_token)
    assert_equal "queued", @gift.reload.delivery_status
    assert_equal "stable-attempt", @gift.delivery_attempt_id
    assert_nil @gift.delivery_error
    assert_redirected_to gift_invitation_url(@old_token)
  end

  test "another user cannot retry a failed delivery" do
    other = User.create!(email: "other@gmail.com", tier: "free", language: "en")
    other.create_tutorial!(terms: true)
    sign_in other

    post retry_delivery_book_gift_url(@gift)

    assert_response :not_found
  end
end
