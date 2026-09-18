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
end
