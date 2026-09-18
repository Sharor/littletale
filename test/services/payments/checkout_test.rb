# frozen_string_literal: true

require "test_helper"

class Payments::CheckoutTest < ActiveSupport::TestCase
  class FakeGateway
    attr_reader :created_sessions, :product

    def initialize(product:, account: { "id" => Payments::Config.account_id }, checkout_errors: [])
      @product = product
      @account = account
      @checkout_errors = checkout_errors
      @created_sessions = []
    end

    def retrieve_account
      @account
    end

    def retrieve_product(product_id)
      raise "wrong product" unless product_id == "prod_VHc1FYY2QqVlJ0"

      @product
    end

    def create_checkout_session(params, idempotency_key:)
      @created_sessions << { params: params, idempotency_key: idempotency_key }
      error = @checkout_errors.shift
      raise error if error

      {
        "id" => "cs_test_checkout",
        "url" => "https://checkout.stripe.test/session",
        "expires_at" => 2.hours.from_now.to_i
      }
    end
  end

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false, stripe_customer_id: nil)
    @gateway = FakeGateway.new(product: {
      "id" => "prod_VHc1FYY2QqVlJ0",
      "active" => true,
      "livemode" => false,
      "default_price" => {
        "id" => "price_book_test",
        "active" => true,
        "type" => "one_time",
        "currency" => "dkk",
        "unit_amount" => 2500
      }
    })
  end

  test "creates one server-priced Checkout session and persists its snapshot" do
    result = Payments::Checkout.call(
      user: @user,
      success_url: "https://example.test/settings?checkout=success&session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "https://example.test/settings?checkout=canceled",
      gateway: @gateway
    )

    purchase = result.purchase
    request = @gateway.created_sessions.fetch(0)
    assert_equal "https://checkout.stripe.test/session", result.url
    assert_equal "pending", purchase.status
    assert_equal "price_book_test", purchase.price_id
    assert_equal 2500, purchase.amount_total
    assert_equal "dkk", purchase.currency
    assert_equal "cs_test_checkout", purchase.stripe_checkout_session_id
    assert_equal purchase.idempotency_key, request[:idempotency_key]
    assert_equal "payment", request.dig(:params, :mode)
    assert_equal [ { price: "price_book_test", quantity: 1 } ], request.dig(:params, :line_items)
    assert_equal purchase.id.to_s, request.dig(:params, :metadata, :purchase_id)
    assert_equal @user.id.to_s, request.dig(:params, :metadata, :user_id)
    assert_equal "always", request.dig(:params, :customer_creation)
    assert_equal @user.email, request.dig(:params, :customer_email)
  end

  test "reuses an unexpired pending Checkout session after a repeated click" do
    first = Payments::Checkout.call(
      user: @user,
      success_url: "https://example.test/settings?checkout=success&session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "https://example.test/settings?checkout=canceled",
      gateway: @gateway
    )
    second = Payments::Checkout.call(
      user: @user,
      success_url: "https://example.test/settings?checkout=success&session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "https://example.test/settings?checkout=canceled",
      gateway: @gateway
    )

    assert_equal first.purchase, second.purchase
    assert_equal first.url, second.url
    assert_equal 1, @gateway.created_sessions.length
  end

  test "uses an existing Stripe customer without accepting price input" do
    @user.update!(stripe_customer_id: "cus_existing")

    Payments::Checkout.call(
      user: @user,
      success_url: "https://example.test/settings?checkout=success&session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "https://example.test/settings?checkout=canceled",
      gateway: @gateway
    )

    params = @gateway.created_sessions.fetch(0).fetch(:params)
    assert_equal "cus_existing", params[:customer]
    assert_not params.key?(:customer_creation)
    assert_not params.key?(:customer_email)
  end

  test "rejects a product without an active one-time default price" do
    gateway = FakeGateway.new(product: {
      "id" => "prod_VHc1FYY2QqVlJ0",
      "active" => true,
      "livemode" => false,
      "default_price" => { "id" => "price_recurring", "active" => true, "type" => "recurring" }
    })

    assert_raises(Payments::Checkout::ConfigurationError) do
      Payments::Checkout.call(user: @user, success_url: "https://example.test/success",
        cancel_url: "https://example.test/cancel", gateway: gateway)
    end
    assert_equal 0, @user.book_purchases.count
  end

  test "rejects a live product outside production" do
    gateway = FakeGateway.new(product: {
      "id" => "prod_VHc1FYY2QqVlJ0",
      "active" => true,
      "livemode" => true,
      "default_price" => {
        "id" => "price_live", "active" => true, "type" => "one_time", "currency" => "dkk", "unit_amount" => 2500
      }
    })

    assert_raises(Payments::Checkout::ConfigurationError) do
      Payments::Checkout.call(user: @user, success_url: "https://example.test/success",
        cancel_url: "https://example.test/cancel", gateway: gateway)
    end
    assert_equal 0, @user.book_purchases.count
  end

  test "rejects a Stripe key for a different configured account" do
    gateway = FakeGateway.new(product: @gateway.product, account: { "id" => "acct_wrong" })

    assert_raises(Payments::Checkout::ConfigurationError) do
      Payments::Checkout.call(user: @user, success_url: "https://example.test/success",
        cancel_url: "https://example.test/cancel", gateway: gateway)
    end
    assert_equal 0, @user.book_purchases.count
  end

  test "retires a pending purchase after a definitive session error so the next click can retry" do
    error = Stripe::InvalidRequestError.new("invalid checkout parameters", "line_items")
    gateway = FakeGateway.new(product: @gateway.product, checkout_errors: [ error ])

    assert_raises(Stripe::InvalidRequestError) do
      Payments::Checkout.call(user: @user, success_url: "https://example.test/success",
        cancel_url: "https://example.test/cancel", gateway: gateway)
    end
    failed = @user.book_purchases.first!
    assert_equal "failed", failed.status
    assert_equal "Stripe::InvalidRequestError", failed.failure_reason

    result = Payments::Checkout.call(user: @user, success_url: "https://example.test/success",
      cancel_url: "https://example.test/cancel", gateway: gateway)

    assert_equal "pending", result.purchase.status
    assert_not_equal failed.idempotency_key, result.purchase.idempotency_key
    assert_equal 2, @user.book_purchases.count
  end
end
