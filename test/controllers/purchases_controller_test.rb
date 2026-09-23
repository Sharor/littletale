# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class PurchasesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "an expired trial can start Checkout from settings" do
    @user.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    result = Payments::Checkout::Result.new(purchase: purchase, url: "https://checkout.stripe.test/pay")
    checkout_arguments = nil

    Payments::Checkout.stub :call, ->(**arguments) { checkout_arguments = arguments; result } do
      post settings_book_purchase_url
    end

    assert_redirected_to "https://checkout.stripe.test/pay"
    assert_includes checkout_arguments.fetch(:success_url), "session_id={CHECKOUT_SESSION_ID}"
  end

  test "gift purchase Checkout returns to the selected book flow" do
    book = @user.books.create!(name: "Trial gift", total_pages: 1, generation_status: :completed, language: "en")
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_test", stripe_checkout_session_id: "cs_gift", idempotency_key: SecureRandom.uuid,
      amount_total: 2500, currency: "dkk", livemode: false)
    result = Payments::Checkout::Result.new(purchase: purchase, url: "https://checkout.stripe.test/gift")
    checkout_arguments = nil

    Payments::Checkout.stub :call, ->(**arguments) { checkout_arguments = arguments; result } do
      post settings_book_purchase_url, params: { gift_book_id: book.id }
    end

    assert_redirected_to "https://checkout.stripe.test/gift"
    assert_equal payment_required_book_book_gifts_url(book), checkout_arguments.fetch(:cancel_url)
  end

  test "successful gift purchase pays for the selected book and opens its giftcard" do
    book = @user.books.create!(name: "Legacy trial gift", total_pages: 1,
      generation_status: :completed, language: "en")
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_test", stripe_checkout_session_id: "cs_gift_success",
      idempotency_key: SecureRandom.uuid, amount_total: 2500, currency: "dkk", livemode: false)
    checkout = Payments::Checkout::Result.new(purchase: purchase, url: "https://checkout.stripe.test/gift-success")
    Payments::Checkout.stub(:call, checkout) do
      post settings_book_purchase_url, params: { gift_book_id: book.id }
    end

    stripe_session = paid_checkout_session(purchase)
    gateway = Object.new
    gateway.define_singleton_method(:retrieve_checkout_session) { |_id| stripe_session }

    Payments::StripeGateway.stub(:new, gateway) do
      get settings_checkout_success_url(session_id: purchase.stripe_checkout_session_id)
    end

    assert_redirected_to new_book_book_gift_url(book)
    assert_predicate purchase.reload, :paid?
    assert_equal "consumed", purchase.book_credit.status
    assert_predicate book.reload, :giftable?
    assert @user.books.exists?(book.id)
  end

  test "gift purchase Checkout rejects a book owned by another user" do
    other = users(:two)
    other_book = other.books.create!(name: "Someone else's book", total_pages: 1,
      generation_status: :completed, language: "en")
    checkout_called = false

    Payments::Checkout.stub :call, ->(**) { checkout_called = true } do
      post settings_book_purchase_url, params: { gift_book_id: other_book.id }
    end

    assert_response :not_found
    assert_not checkout_called
  end

  test "Checkout creation requires authentication" do
    sign_out @user

    post settings_book_purchase_url

    assert_redirected_to new_user_session_url
  end

  test "success only fulfills a Checkout session owned by the signed-in user" do
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_test", stripe_checkout_session_id: "cs_owned", idempotency_key: SecureRandom.uuid,
      amount_total: 2500, currency: "dkk", livemode: false)
    gateway = Object.new
    gateway.define_singleton_method(:retrieve_checkout_session) { |_id| { "id" => "cs_owned" } }
    fulfilled = nil

    Payments::StripeGateway.stub :new, gateway do
      Payments::FulfillCheckout.stub :call, ->(session:) { fulfilled = session; true } do
        get settings_checkout_success_url(session_id: "cs_owned")
      end
    end

    assert_equal({ "id" => "cs_owned" }, fulfilled)
    assert_redirected_to settings_url(checkout: "success")

    other_purchase = users(:two).book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_test", stripe_checkout_session_id: "cs_foreign", idempotency_key: SecureRandom.uuid,
      amount_total: 2500, currency: "dkk", livemode: false)
    assert other_purchase
    get settings_checkout_success_url(session_id: "cs_foreign")
    assert_response :not_found
  end

  test "an unpaid success redirect remains pending" do
    @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_test", stripe_checkout_session_id: "cs_pending", idempotency_key: SecureRandom.uuid,
      amount_total: 2500, currency: "dkk", livemode: false)
    gateway = Object.new
    gateway.define_singleton_method(:retrieve_checkout_session) { |_id| { "id" => "cs_pending" } }

    Payments::StripeGateway.stub :new, gateway do
      Payments::FulfillCheckout.stub :call, ->(session:) { raise Payments::FulfillCheckout::InvalidSession, "unpaid" } do
        get settings_checkout_success_url(session_id: "cs_pending")
      end
    end

    assert_redirected_to settings_url(checkout: "pending")
  end

  private

  def paid_checkout_session(purchase)
    {
      "id" => purchase.stripe_checkout_session_id,
      "mode" => "payment",
      "payment_status" => "paid",
      "livemode" => false,
      "amount_total" => 2500,
      "currency" => "dkk",
      "metadata" => {
        "purchase_id" => purchase.id.to_s,
        "user_id" => @user.id.to_s,
        "product_id" => BookPurchase::PRODUCT_ID
      },
      "line_items" => {
        "data" => [ {
          "quantity" => 1,
          "price" => { "id" => "price_test", "product" => BookPurchase::PRODUCT_ID, "type" => "one_time" }
        } ]
      },
      "customer" => "cus_gift",
      "payment_intent" => "pi_gift"
    }
  end
end
