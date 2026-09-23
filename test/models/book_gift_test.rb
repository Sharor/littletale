# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BookGiftTest < ActiveSupport::TestCase
  setup do
    @sender = users(:one)
    @sender.update!(tier: "basic", admin: false)
    @book = @sender.books.create!(
      name: "The Paid Adventure",
      total_pages: 1,
      generation_status: :completed,
      language: "en"
    )
    @book.pages.create!(text: "Once upon a paid-for time.", story_position: 1)
    fund_with_paid_purchase(@book)
  end

  test "a completed book funded by a consumed paid credit is giftable" do
    assert_predicate @book, :giftable?
  end

  test "a completed trial-funded book is not giftable" do
    @book.book_credit_reservations.delete_all
    TrialBookReservation.create!(user: @sender, book: @book, status: "held")

    assert_not @book.giftable?
  end

  test "an unfinished book is not giftable even when its credit was paid" do
    @book.update!(generation_status: :in_progress)

    assert_not @book.giftable?
  end

  test "a released paid reservation is not giftable" do
    @book.book_credit_reservations.update_all(status: "released")

    assert_not @book.giftable?
  end

  test "a consumed credit from an unpaid purchase is not giftable" do
    purchase = @book.book_credit_reservations.first.book_credit.book_purchase
    purchase.update_columns(status: "pending", paid_at: nil)

    assert_not @book.giftable?
  end

  test "a completed book funded by a paid subscription period is giftable" do
    @book.book_credit_reservations.delete_all
    subscription = @sender.user_subscriptions.create!(
      status: "canceled",
      product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid
    )
    period = subscription.subscription_periods.create!(
      stripe_invoice_id: "in_#{SecureRandom.hex(8)}",
      price_id: "price_monthly",
      period_start: 1.month.ago,
      period_end: 1.month.from_now
    )
    credit = @sender.book_credits.create!(subscription_period: period, status: "consumed", visible: false)
    @sender.book_credit_reservations.create!(
      book: @book,
      book_credit: credit,
      status: "consumed",
      consumed_at: Time.current
    )

    assert_predicate @book, :giftable?
  end

  test "gift requires all giftcard fields and a Gmail recipient" do
    gift = BookGift.new(source_book: @book, sender: @sender, language: "en")

    assert_not gift.valid?
    assert gift.errors.added?(:recipient_name, :blank)
    assert gift.errors.added?(:recipient_email, :blank)
    assert gift.errors.added?(:sender_callname, :blank)
    assert gift.errors.added?(:message, :blank)

    gift.assign_attributes(valid_attributes(recipient_email: "reader@outlook.com"))
    assert_not gift.valid?
    assert gift.errors.added?(:recipient_email, :gmail_only)
  end

  test "issuing a gift snapshots the finished book and returns a raw token once" do
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)

    assert_equal "The Paid Adventure", gift.title
    assert_equal [ "Once upon a paid-for time." ], gift.gift_pages.order(:position).pluck(:text)
    assert_not_nil gift.invitation_token
    assert_not_equal gift.invitation_token, gift.token_digest
    assert_equal gift, BookGift.find_by_invitation_token(gift.invitation_token)
    assert_nil gift.reload.invitation_token
  end

  test "repeating an issuance key returns the same retained gift and token" do
    attributes = valid_attributes(issuance_key: SecureRandom.uuid)
    first = nil
    second = nil

    assert_difference("BookGift.count", 1) do
      first = BookGift.issue!(source_book: @book, sender: @sender, attributes: attributes)
      second = BookGift.issue!(source_book: @book, sender: @sender, attributes: attributes)
    end

    assert_equal first, second
    assert_equal first.invitation_token, second.invitation_token
    assert_predicate first, :issued_now?
    assert_not second.issued_now?
    assert_not_includes first.invitation_token_ciphertext, first.invitation_token
  end

  test "an image upload failure removes the unpublished retained gift" do
    source_path = Rails.root.join("test/fixtures/files/character.png")
    illustration = Illustration.new(page: @book.pages.first)
    File.open(source_path, "rb") { |file| illustration.original_image = file }
    illustration.save!
    service = ActiveStorage::Blob.service

    assert_no_difference([ "BookGift.count", "GiftPage.count" ]) do
      service.stub(:upload, ->(*, **) { raise IOError, "storage unavailable" }) do
        assert_raises(IOError) do
          BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
        end
      end
    end
  end

  test "only the Gmail account named on the invitation can claim it" do
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
    wrong_user = User.create!(email: "other@gmail.com", tier: "free", language: "en")
    recipient = User.create!(email: "READER@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)

    assert_raises(BookGift::RecipientMismatch) { gift.claim!(wrong_user) }
    assert gift.claim!(recipient)
    assert_equal recipient, gift.reload.recipient
    assert_not_nil gift.claimed_at
  end

  test "claiming a gift does not start a trial or consume recipient credit" do
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
    recipient = User.create!(email: "reader@gmail.com", tier: "free", language: "en",
      google_email_verified_at: Time.current)
    credit_count = recipient.book_credits.count

    gift.claim!(recipient)

    assert_nil recipient.reload.trial_started_at
    assert_nil recipient.trial_expires_at
    assert_equal credit_count, recipient.book_credits.count
  end

  test "claiming requires Google to have verified the matching email" do
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
    recipient = User.create!(email: "reader@gmail.com", tier: "free", language: "en")

    assert_raises(BookGift::UnverifiedRecipient) { gift.claim!(recipient) }
    assert_nil gift.reload.recipient
  end

  test "the retained gift survives deletion of the source book" do
    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)

    @book.destroy!

    assert_nil gift.reload.source_book
    assert_equal "The Paid Adventure", gift.title
    assert_equal "Once upon a paid-for time.", gift.gift_pages.first.text
  end

  test "the retained gift copies page image bytes before source deletion" do
    source_path = Rails.root.join("test/fixtures/files/character.png")
    illustration = Illustration.new(page: @book.pages.first)
    File.open(source_path, "rb") { |file| illustration.original_image = file }
    illustration.save!

    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)
    retained_page = gift.gift_pages.first
    assert_predicate retained_page.image, :attached?
    assert_equal File.binread(source_path), retained_page.image.download

    @book.destroy!

    assert_equal File.binread(source_path), retained_page.reload.image.download
  end

  test "snapshot positions are stable even when source story positions collide" do
    @book.pages.first.update_column(:story_position, nil)
    @book.pages.create!(text: "A second moment.", story_position: 1)

    gift = BookGift.issue!(source_book: @book, sender: @sender, attributes: valid_attributes)

    assert_equal [ 1, 2 ], gift.gift_pages.pluck(:position)
    assert_equal [ "Once upon a paid-for time.", "A second moment." ], gift.gift_pages.pluck(:text)
  end

  private

  def valid_attributes(overrides = {})
    {
      recipient_name: "Reader",
      recipient_email: "reader@gmail.com",
      sender_callname: "Aunt Alex",
      message: "I hope you love this adventure.",
      language: "en"
    }.merge(overrides)
  end

  def fund_with_paid_purchase(book)
    purchase = @sender.book_purchases.create!(
      status: "paid",
      product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid,
      stripe_checkout_session_id: "cs_#{SecureRandom.hex(8)}",
      stripe_payment_intent_id: "pi_#{SecureRandom.hex(8)}",
      stripe_customer_id: "cus_#{SecureRandom.hex(8)}",
      amount_total: 2500,
      currency: "dkk",
      paid_at: Time.current
    )
    credit = @sender.book_credits.create!(book_purchase: purchase, status: "consumed")
    @sender.book_credit_reservations.create!(
      book: book,
      book_credit: credit,
      status: "consumed",
      consumed_at: Time.current
    )
  end
end
