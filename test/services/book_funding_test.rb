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
  end
end
