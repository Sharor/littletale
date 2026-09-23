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

  test "library places a gift action below Read and keeps the source book" do
    sign_in @sender

    get books_url

    assert_response :success
    assert_select "article.library-book" do
      assert_select ".library-book-actions" do
        assert_select "a.library-read[href='#{book_path(@book)}']", text: "Read"
        assert_select "form.library-gift-form[action='#{prepare_book_book_gifts_path(@book)}']" do
          assert_select "button.library-gift-action", text: "Send as gift"
        end
        assert_select "[data-controller='gift-modal']", count: 0
      end
    end
    assert @sender.books.exists?(@book.id)
  end

  test "completed trial book without a reservation still shows both gift actions" do
    @sender.update!(tier: "free")
    trial_book = @sender.books.create!(name: "Legacy Trial Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    page = trial_book.pages.create!(text: "A trial story.", story_position: 1)
    illustration = page.create_illustration!
    File.open(file_fixture("character.png"), "rb") { |file| illustration.update!(original_image: file) }
    sign_in @sender

    get books_url

    assert_response :success
    assert_select "form[action='#{prepare_book_book_gifts_path(trial_book)}'] button",
      text: "Send as gift"
    assert_select "form[action='#{prepare_book_book_gifts_path(trial_book)}'] button[data-turbo-confirm]", count: 0
    assert_select "[data-controller='gift-modal']" do
      assert_select "form.library-gift-form[data-action='submit->gift-modal#open']"
      assert_select "dialog.fable-dialog-shell[data-gift-modal-target='dialog']" do
        assert_select "h2", text: 'Buy the book "Legacy Trial Adventure" to send it as a gift'
        assert_select "form[action='#{settings_book_purchase_path}'] input[name='gift_book_id'][value='#{trial_book.id}']"
        assert_select "button[data-action='gift-modal#close']", text: "Cancel"
      end
    end

    get book_url(trial_book)

    assert_response :success
    assert_select ".page-cover-bottom form[action='#{prepare_book_book_gifts_path(trial_book)}'] button",
      text: "Gift copy of this book"
  end

  test "trial-funded book with an available credit uses an in-page confirmation modal" do
    trial_book = @sender.books.create!(name: "Credit Trial Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    @sender.trial_book_reservations.create!(book: trial_book)
    create_available_credit(@sender)
    sign_in @sender

    get books_url

    assert_response :success
    assert_select "[data-controller='gift-modal']" do
      assert_select "form.library-gift-form[data-action='submit->gift-modal#open']"
      assert_select "dialog.fable-dialog-shell[data-gift-modal-target='dialog']" do
        assert_select "h2", text: "Use one book credit?"
        assert_select "form[action='#{prepare_book_book_gifts_path(trial_book)}'] button",
          text: "Use credit and continue"
        assert_select "form[action='#{settings_book_purchase_path}']", count: 0
      end
    end
  end

  test "reader places the gift action below Back to Library Overview on the final page" do
    sign_in @sender

    get book_url(@book)

    assert_response :success
    assert_select ".page-cover-bottom .book-end-actions" do
      assert_select "a.book-back-button[href='#{books_path}']", text: "Back to Library Overview"
      assert_select "form.book-gift-copy-form[action='#{prepare_book_book_gifts_path(@book)}']" do
        assert_select "button.book-gift-copy-button", text: "Gift copy of this book"
      end
    end
    assert_select ".gift-book-action", count: 0
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
    page = book.pages.create!(text: "Once upon a paid-for time.", story_position: 1)
    illustration = page.create_illustration!
    File.open(file_fixture("character.png"), "rb") { |file| illustration.update!(original_image: file) }
    purchase = owner.book_purchases.create!(status: "paid", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, stripe_checkout_session_id: "cs_nav_#{SecureRandom.hex(6)}",
      stripe_payment_intent_id: "pi_nav_#{SecureRandom.hex(6)}", stripe_customer_id: "cus_nav",
      amount_total: 2500, currency: "dkk", paid_at: Time.current)
    credit = owner.book_credits.create!(book_purchase: purchase, status: "consumed")
    owner.book_credit_reservations.create!(book: book, book_credit: credit, status: "consumed",
      consumed_at: Time.current)
    book
  end

  def create_available_credit(owner)
    purchase = owner.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_nav_#{SecureRandom.hex(6)}",
      payment_intent_id: "pi_nav_#{SecureRandom.hex(6)}", stripe_customer_id: "cus_nav_credit",
      price_id: "price_test", amount_total: 2500, currency: "dkk")
    purchase.book_credit
  end
end
