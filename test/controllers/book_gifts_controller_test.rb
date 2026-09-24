# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BookGiftsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @sender = users(:one)
    @sender.update!(tier: "basic", admin: false, name: "Alex", language: "en")
    @sender.tutorial.update!(terms: true)
    @book = create_paid_book(@sender)
    sign_in @sender
  end

  test "preparing an already paid book opens the giftcard without spending another credit" do
    assert_no_difference("@sender.book_credit_reservations.count") do
      post prepare_book_book_gifts_url(@book)
    end

    assert_redirected_to new_book_book_gift_url(@book)
    assert_predicate @book.reload, :giftable?
  end

  test "preparing a trial book consumes a paid credit and releases the trial slot" do
    trial_book = @sender.books.create!(name: "Trial gift", total_pages: 1,
      generation_status: :completed, language: "en")
    trial_reservation = @sender.trial_book_reservations.create!(book: trial_book)
    credit = create_available_credit(@sender)

    assert_no_difference("Book.count") do
      post prepare_book_book_gifts_url(trial_book)
    end

    assert_redirected_to new_book_book_gift_url(trial_book)
    assert_equal "consumed", credit.reload.status
    assert_equal "released", trial_reservation.reload.status
    assert_predicate trial_book.reload, :giftable?
    assert @sender.books.exists?(trial_book.id)
  end

  test "preparing an unpaid book without a credit opens the gift purchase explanation" do
    trial_book = @sender.books.create!(name: "Trial gift", total_pages: 1,
      generation_status: :completed, language: "en")
    trial_reservation = @sender.trial_book_reservations.create!(book: trial_book)

    assert_no_difference("BookCreditReservation.count") do
      post prepare_book_book_gifts_url(trial_book)
    end

    assert_redirected_to "/books/#{trial_book.id}/book_gifts/payment_required"
    assert_equal "held", trial_reservation.reload.status
  end

  test "trial account sees the purchase explanation even if an available credit exists" do
    trial_book = @sender.books.create!(name: "Trial gift", total_pages: 1,
      generation_status: :completed, language: "en")
    trial_reservation = @sender.trial_book_reservations.create!(book: trial_book)
    credit = create_available_credit(@sender)
    @sender.update!(tier: "free")

    post prepare_book_book_gifts_url(trial_book)

    assert_redirected_to payment_required_book_book_gifts_url(trial_book)
    assert_equal "available", credit.reload.status
    assert_equal "held", trial_reservation.reload.status
  end

  test "gift purchase explanation offers to buy the selected book" do
    trial_book = @sender.books.create!(name: "Trial gift", total_pages: 1,
      generation_status: :completed, language: "en")

    get payment_required_book_book_gifts_url(trial_book)

    assert_response :success
    assert_select "[role='dialog'][aria-modal='true']" do
      assert_select "h2", text: "Buy the book \"Trial gift\" to send it as a gift"
    end
    assert_select "p", text: /original book stays in your library/i
    assert_select "form[action='#{settings_book_purchase_path}']" do
      assert_select "input[name='gift_book_id'][value='#{trial_book.id}']"
      assert_select "button", text: "Buy the book"
    end
    assert_select "a[href='#{books_path}']", text: "Back to library"
  end

  test "gift purchase explanation is unavailable until the book is completed" do
    pending_book = @sender.books.create!(name: "Still writing", total_pages: 1, language: "en")

    get payment_required_book_book_gifts_url(pending_book)

    assert_response :not_found
  end

  test "owner can open the giftcard for a paid completed book" do
    get new_book_book_gift_url(@book)

    assert_response :success
    assert_select "form[action='#{book_book_gifts_path(@book)}']" do
      assert_select "[data-gift-message-el-value]", count: 1
      assert_select "input[name='book_gift[recipient_name]'][required]"
      assert_select "input[name='book_gift[recipient_email]'][type='email'][required]"
      assert_select "input[name='book_gift[recipient_email]'][pattern]", count: 0
      assert_select "input[name='book_gift[issuance_key]'][type='hidden']"
      assert_select "input[name='book_gift[sender_callname]'][value='Alex'][required]"
      assert_select "textarea[name='book_gift[message]'][required]", text: /adventure/i
      assert_select "select[name='book_gift[language]'] option[value='en'][selected]"
      assert_select "select[name='book_gift[language]'] option[value='el']", "Ελληνικά"
      assert_select "button[name='delivery'][value='email']"
      assert_select "button[name='delivery'][value='link']"
    end
  end

  test "owner cannot gift an unpaid book" do
    unpaid = @sender.books.create!(name: "Trial Book", total_pages: 1, generation_status: :completed)

    get new_book_book_gift_url(unpaid)

    assert_response :not_found
  end

  test "creating a share link retains the gift without spending another credit" do
    credit_count = @sender.book_credits.count

    assert_difference("BookGift.count", 1) do
      post book_book_gifts_url(@book), params: { book_gift: valid_attributes, delivery: "link" }
    end

    gift = BookGift.order(:id).last
    assert_equal credit_count, @sender.reload.book_credits.count
    assert_equal "not_sent", gift.delivery_status
    token = URI(response.location).path.split("/").last
    assert_equal gift, BookGift.find_by_invitation_token(token)
    assert_redirected_to gift_invitation_url(token)
  end

  test "email delivery queues one invitation and records queue state" do
    assert_enqueued_jobs 1, only: DeliverGiftEmailJob do
      post book_book_gifts_url(@book), params: { book_gift: valid_attributes, delivery: "email" }
    end

    gift = BookGift.order(:id).last
    assert_equal "queued", gift.delivery_status
    assert_not_nil gift.email_queued_at
  end

  test "repeating the same email submission creates and queues one gift" do
    attributes = valid_attributes

    assert_difference("BookGift.count", 1) do
      assert_enqueued_jobs 1, only: DeliverGiftEmailJob do
        2.times do
          post book_book_gifts_url(@book), params: { book_gift: attributes, delivery: "email" }
        end
      end
    end
  end

  test "a fast delivery worker is not overwritten back to queued" do
    perform_enqueued_jobs do
      post book_book_gifts_url(@book), params: { book_gift: valid_attributes, delivery: "email" }
    end

    gift = BookGift.order(:id).last
    assert_equal "sent", gift.delivery_status
    assert_not_nil gift.delivered_at
  end

  test "queue handoff failure keeps the gift and opens its retry page" do
    enqueue_error = SolidQueue::Job::EnqueueError.new("queue unavailable")

    assert_difference("BookGift.count", 1) do
      DeliverGiftEmailJob.stub(:perform_later, ->(*) { raise enqueue_error }) do
        post book_book_gifts_url(@book), params: { book_gift: valid_attributes, delivery: "email" }
      end
    end

    gift = BookGift.order(:id).last
    token = URI(response.location).path.split("/").last
    assert_equal "failed", gift.delivery_status
    assert_match "queue unavailable", gift.delivery_error
    assert_equal gift, BookGift.find_by_invitation_token(token)
    assert_redirected_to gift_invitation_url(token)
  end

  test "server rejects a non Gmail recipient" do
    assert_no_difference("BookGift.count") do
      post book_book_gifts_url(@book), params: {
        book_gift: valid_attributes.merge(recipient_email: "reader@outlook.com"), delivery: "link"
      }
    end

    assert_response :unprocessable_content
    assert_select "form[action='#{book_book_gifts_path(@book)}']"
  end

  test "invitation GET never claims the gift" do
    gift, token = issue_gift
    sign_out @sender

    get gift_invitation_url(token)

    assert_response :success
    assert_nil gift.reload.claimed_at
    assert_select "a[href='#{new_user_session_path}']", text: /sign in/i
  end

  test "matching verified Gmail account explicitly claims the gift" do
    gift, token = issue_gift
    recipient = verified_recipient
    sign_in recipient

    post claim_gift_invitation_url(token)

    assert_redirected_to received_gift_url(gift)
    assert_equal recipient, gift.reload.recipient
    assert_nil recipient.reload.trial_started_at
  end

  test "wrong account cannot claim or read the gift" do
    gift, token = issue_gift
    wrong_user = User.create!(email: "wrong@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)
    wrong_user.create_tutorial!(terms: true)
    sign_in wrong_user

    post claim_gift_invitation_url(token)
    assert_response :forbidden

    get received_gift_url(gift)
    assert_response :not_found
  end

  test "wrong account can switch to the invited account and claim" do
    gift, token = issue_gift
    wrong_user = User.create!(email: "wrong-switch@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)
    wrong_user.create_tutorial!(terms: true)
    recipient = verified_recipient
    sign_in wrong_user

    get gift_invitation_url(token)
    assert_select "form[action='#{switch_account_gift_invitation_path(token)}']"

    post switch_account_gift_invitation_url(token)
    assert_redirected_to gift_invitation_url(token)
    follow_redirect!
    assert_select "a[href='#{new_user_session_path}']", text: /sign in/i

    sign_in recipient
    post claim_gift_invitation_url(token)
    assert_redirected_to received_gift_url(gift)
    assert_equal recipient, gift.reload.recipient
  end

  test "retained images are served only through the claimed recipient route" do
    source_path = Rails.root.join("test/fixtures/files/character.png")
    illustration = Illustration.new(page: @book.pages.first)
    File.open(source_path, "rb") { |file| illustration.original_image = file }
    illustration.save!
    gift, = issue_gift
    recipient = verified_recipient
    gift.claim!(recipient)
    page = gift.gift_pages.first
    image_path = received_gift_page_image_path(gift, page)
    sign_in recipient

    get received_gifts_url
    assert_select "img[src='#{image_path}']"

    get received_gift_url(gift)
    assert_select "img[src='#{image_path}']"
    get image_path
    assert_response :success
    assert_equal File.binread(source_path), response.body

    sign_out recipient
    get image_path
    assert_redirected_to new_user_session_url

    wrong_user = User.create!(email: "wrong-image@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)
    wrong_user.create_tutorial!(terms: true)
    sign_in wrong_user
    get image_path
    assert_response :not_found
  end

  test "expired trial recipient can list and read a claimed gift" do
    gift, = issue_gift
    recipient = verified_recipient
    recipient.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)
    gift.claim!(recipient)
    sign_in recipient

    get received_gifts_url
    assert_response :success
    assert_select "h3", gift.title

    get received_gift_url(gift)
    assert_response :success
    assert_select ".story-body", "Once upon a paid-for time."
    assert_select "a[href^='#{new_book_book_gift_path(@book)}']", count: 0
  end

  private

  def valid_attributes
    {
      recipient_name: "Reader",
      recipient_email: "reader@gmail.com",
      sender_callname: "Alex",
      message: "I hope you love this adventure.",
      language: "en",
      issuance_key: SecureRandom.uuid
    }
  end

  def verified_recipient
    User.create!(email: "reader@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current).tap { |user| user.create_tutorial!(terms: true) }
  end

  def issue_gift
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
    [ gift, gift.invitation_token ]
  end

  def create_available_credit(owner)
    purchase = owner.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_#{SecureRandom.hex(8)}",
      payment_intent_id: "pi_#{SecureRandom.hex(8)}", stripe_customer_id: "cus_#{SecureRandom.hex(8)}",
      price_id: "price_test", amount_total: 2500, currency: "dkk")
    purchase.book_credit
  end

  def create_paid_book(owner)
    book = owner.books.create!(name: "The Paid Adventure", total_pages: 1,
      generation_status: :completed, language: "en")
    book.pages.create!(text: "Once upon a paid-for time.", story_position: 1)
    purchase = owner.book_purchases.create!(status: "paid", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, stripe_checkout_session_id: "cs_#{SecureRandom.hex(8)}",
      stripe_payment_intent_id: "pi_#{SecureRandom.hex(8)}", stripe_customer_id: "cus_#{SecureRandom.hex(8)}",
      amount_total: 2500, currency: "dkk", paid_at: Time.current)
    credit = owner.book_credits.create!(book_purchase: purchase, status: "consumed")
    owner.book_credit_reservations.create!(book: book, book_credit: credit, status: "consumed",
      consumed_at: Time.current)
    book
  end
end
