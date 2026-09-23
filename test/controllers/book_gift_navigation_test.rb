# frozen_string_literal: true

require "test_helper"

class BookGiftNavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @sender = users(:one)
    @sender.update!(tier: "basic", admin: false, name: "Alex", language: "en")
    @sender.tutorial.update!(terms: true)
    @book = paid_book_for(@sender)
    @gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: {
      recipient_name: "Reader", recipient_email: "reader@gmail.com", sender_callname: "Alex",
      message: "I hope you love this adventure.", language: "en"
    })
    @token = @gift.invitation_token
  end

  test "paid completed book shows an owner-only gift action" do
    sign_in @sender

    get book_url(@book)

    assert_response :success
    assert_select "a[href='#{new_book_book_gift_path(@book)}']", text: /gift/i
  end

  test "pending invitation survives terms and language onboarding" do
    recipient = User.create!(email: "reader@gmail.com", tier: "free", language: nil,
      google_email_verified_at: Time.current)
    recipient.create_tutorial!(terms: false)

    get gift_invitation_url(@token)
    assert_response :success
    sign_in recipient

    get gift_invitation_url(@token)
    assert_redirected_to terms_url

    post accept_terms_url
    assert_redirected_to profile_url(onboarding: true)

    patch profile_url, params: { onboarding: true, user: { language: "en", reader_age: "" } }
    assert_redirected_to gift_invitation_url(@token)
    assert_nil @gift.reload.claimed_at
  end

  test "claimed gifts appear in the recipient library and navigation" do
    recipient = User.create!(email: "reader@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)
    recipient.create_tutorial!(terms: true)
    @gift.claim!(recipient)
    sign_in recipient

    get books_url

    assert_response :success
    assert_select "h2", text: /Gifted to you/
    assert_select "a[href='#{received_gift_path(@gift)}']"
    assert_select "a[href='#{received_gifts_path}']", text: /Gifts/
  end

  private

  def paid_book_for(owner)
    book = owner.books.create!(name: "The Paid Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    book.pages.create!(text: "Once upon a paid-for time.", story_position: 1)
    purchase = owner.book_purchases.create!(status: "paid", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, stripe_checkout_session_id: "cs_nav_#{SecureRandom.hex(6)}",
      stripe_payment_intent_id: "pi_nav_#{SecureRandom.hex(6)}", stripe_customer_id: "cus_nav",
      amount_total: 2500, currency: "dkk", paid_at: Time.current)
    credit = owner.book_credits.create!(book_purchase: purchase, status: "consumed")
    owner.book_credit_reservations.create!(book: book, book_credit: credit, status: "consumed",
      consumed_at: Time.current)
    book
  end
end
