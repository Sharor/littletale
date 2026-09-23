# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BookFundingTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
  end

  test "a Basic book reserves its purchased credit and completion consumes it" do
    fulfill_purchase
    book = @user.books.create!(name: "Paid tale", total_pages: 1)

    reservation = BookFunding.reserve_for!(book)

    assert_instance_of BookCreditReservation, reservation
    assert_equal 0, @user.available_book_credits
    book.update!(generation_status: :completed)
    assert_equal "consumed", reservation.reload.status
    assert_equal 0, @user.available_book_credits
  end

  test "an existing trial-funded book keeps its trial funding after upgrade" do
    book = @user.books.create!(name: "Trial tale", total_pages: 1)
    trial_reservation = TrialBookReservation.reserve_for!(book)
    fulfill_purchase

    assert_equal trial_reservation, BookFunding.reserve_for!(book)
    assert_empty book.book_credit_reservations
    assert_equal 1, @user.available_book_credits
  end

  test "gifting converts a completed trial book to paid funding and releases its trial slot" do
    book = @user.books.create!(name: "Trial gift", total_pages: 1, generation_status: :completed)
    trial_reservation = TrialBookReservation.reserve_for!(book)
    fulfill_purchase

    assert_no_difference("Book.count") do
      reservation = BookFunding.convert_trial_to_paid_for_gift!(book)

      assert_instance_of BookCreditReservation, reservation
      assert_equal "consumed", reservation.status
      assert_equal "consumed", reservation.book_credit.status
    end

    assert_equal "released", trial_reservation.reload.status
    assert_equal "converted_to_paid_for_gift", trial_reservation.release_reason
    assert_predicate book.reload, :giftable?
  end

  test "gifting can pay for a completed legacy trial book without a reservation" do
    book = @user.books.create!(name: "Legacy trial gift", total_pages: 1, generation_status: :completed)
    credit = fulfill_purchase.book_credit

    reservation = BookFunding.convert_trial_to_paid_for_gift!(book)

    assert_equal book, reservation.book
    assert_equal "consumed", reservation.status
    assert_equal "consumed", credit.reload.status
    assert_predicate book.reload, :giftable?
  end

  test "gifting leaves trial funding unchanged when no paid credit is available" do
    book = @user.books.create!(name: "Unpaid trial gift", total_pages: 1, generation_status: :completed)
    trial_reservation = TrialBookReservation.reserve_for!(book)

    assert_raises(BookCredit::LimitReached) do
      BookFunding.convert_trial_to_paid_for_gift!(book)
    end

    assert_equal "held", trial_reservation.reload.status
    assert_empty book.book_credit_reservations
  end

  test "gifting an already paid book does not consume another credit" do
    fulfill_purchase
    paid_book = @user.books.create!(name: "Paid gift", total_pages: 1)
    reservation = BookFunding.reserve_for!(paid_book)
    paid_book.update!(generation_status: :completed)
    fulfill_purchase

    assert_no_difference("@user.reload.available_book_credits") do
      assert_equal reservation, BookFunding.convert_trial_to_paid_for_gift!(paid_book)
    end
  end

  test "a Basic user cannot fund a second book without another credit" do
    fulfill_purchase
    first = @user.books.create!(name: "First", total_pages: 1)
    second = @user.books.create!(name: "Second", total_pages: 1)
    BookFunding.reserve_for!(first)

    assert_raises(BookCredit::LimitReached) { BookFunding.reserve_for!(second) }
  end

  test "a completed paid book keeps its original funding for later retries" do
    fulfill_purchase
    book = @user.books.create!(name: "Completed paid tale", total_pages: 1)
    reservation = BookFunding.reserve_for!(book)
    book.update!(generation_status: :completed)

    assert_equal "consumed", reservation.reload.status
    assert_equal reservation, BookFunding.reserve_for!(book)
    assert_equal 1, book.book_credit_reservations.count
    assert_equal "book_credit", book.generation_failure_context("type" => "retry_failed")["funding_source"]
  end

  test "a retry queue failure does not claim a consumed credit was released" do
    fulfill_purchase
    book = @user.books.create!(name: "Paid retry", total_pages: 1)
    reservation = BookFunding.reserve_for!(book)
    book.update!(generation_status: :completed)
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    GenerateBookJob.stub(:perform_later, failed_job) do
      assert_not book.enqueue_generation!
    end

    assert_equal "consumed", reservation.reload.status
    assert_equal "Book generation could not be queued.", book.reload.generation_failure.fetch("message")
  end

  test "an administrator can generate without credits" do
    @user.update!(admin: true)
    book = @user.books.create!(name: "Admin tale", total_pages: 1)

    assert_nil BookFunding.reserve_for!(book)
  end

  test "paid generation failures retain their funding audit references" do
    fulfill_purchase
    book = @user.books.create!(name: "Failed paid tale", total_pages: 1)
    reservation = BookFunding.reserve_for!(book)

    context = book.generation_failure_context("type" => "provider_error")

    assert_equal "paid", context["account_access"]
    assert_equal "book_credit", context["funding_source"]
    assert_equal reservation.id, context["funding_reservation_id"]
    assert_equal reservation.book_credit.book_purchase_id, context["purchase_id"]
  end

  private

  def fulfill_purchase
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_#{SecureRandom.hex}", payment_intent_id: "pi_#{SecureRandom.hex}",
      stripe_customer_id: "cus_#{@user.id}", price_id: "price_test", amount_total: 2500, currency: "dkk")
    purchase
  end
end
