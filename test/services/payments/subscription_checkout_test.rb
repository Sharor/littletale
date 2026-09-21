# frozen_string_literal: true

require "test_helper"

class Payments::SubscriptionCheckoutTest < ActiveSupport::TestCase
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
      raise "wrong product" unless product_id == UserSubscription::PRODUCT_ID

      product
    end

    def create_checkout_session(params, idempotency_key:)
      @created_sessions << { params: params, idempotency_key: idempotency_key }
      error = @checkout_errors.shift
      raise error if error

      {
        "id" => "cs_subscription",
        "url" => "https://checkout.stripe.test/subscription",
        "expires_at" => 2.hours.from_now.to_i
      }
    end
  end

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false, stripe_customer_id: nil)
    @gateway = FakeGateway.new(product: monthly_product)
  end

  test "creates a monthly subscription Checkout with server-owned metadata" do
    result = Payments::SubscriptionCheckout.call(
      user: @user,
      success_url: "https://example.test/settings?subscription=success",
      cancel_url: "https://example.test/settings?subscription=canceled",
      gateway: @gateway
    )

    subscription = result.subscription
    params = @gateway.created_sessions.fetch(0).fetch(:params)
    assert_equal "https://checkout.stripe.test/subscription", result.url
    assert_equal "pending", subscription.status
    assert_equal "price_monthly", subscription.price_id
    assert_equal "cs_subscription", subscription.stripe_checkout_session_id
    assert_equal "subscription", params[:mode]
    assert_equal [ { price: "price_monthly", quantity: 1 } ], params[:line_items]
    assert_equal @user.id.to_s, params.dig(:metadata, :user_id)
    assert_equal subscription.id.to_s, params.dig(:metadata, :user_subscription_id)
    assert_equal subscription.id.to_s, params.dig(:subscription_data, :metadata, :user_subscription_id)
    assert_equal UserSubscription::PRODUCT_ID, params.dig(:subscription_data, :metadata, :product_id)
    assert_equal @user.email, params[:customer_email]
    assert_not params.key?(:customer_creation)
  end

  test "reuses an unexpired pending subscription Checkout" do
    first = start_checkout
    second = start_checkout

    assert_equal first.subscription, second.subscription
    assert_equal first.url, second.url
    assert_equal 1, @gateway.created_sessions.length
  end

  test "retires an expired pending Checkout before starting another" do
    expired = @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_checkout_session_id: "cs_expired",
      checkout_url: "https://checkout.stripe.test/expired",
      checkout_expires_at: 1.minute.ago,
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )

    result = start_checkout

    assert_equal "incomplete_expired", expired.reload.status
    assert_not_equal expired, result.subscription
    assert_equal "pending", result.subscription.status
    assert_equal 2, @user.user_subscriptions.count
  end

  test "retries an uncertain Stripe request with the same pending record and idempotency key" do
    gateway = FakeGateway.new(
      product: monthly_product,
      checkout_errors: [ Stripe::APIConnectionError.new("connection closed") ]
    )

    assert_raises(Stripe::APIConnectionError) do
      Payments::SubscriptionCheckout.call(
        user: @user,
        success_url: "https://example.test/success",
        cancel_url: "https://example.test/cancel",
        gateway: gateway
      )
    end
    pending = @user.user_subscriptions.sole

    result = Payments::SubscriptionCheckout.call(
      user: @user,
      success_url: "https://example.test/success",
      cancel_url: "https://example.test/cancel",
      gateway: gateway
    )

    assert_equal pending, result.subscription
    assert_equal 2, gateway.created_sessions.length
    assert_equal [ pending.idempotency_key ], gateway.created_sessions.map { |request| request[:idempotency_key] }.uniq
  end

  test "uses the existing Stripe customer" do
    @user.update!(stripe_customer_id: "cus_existing")

    start_checkout

    params = @gateway.created_sessions.fetch(0).fetch(:params)
    assert_equal "cus_existing", params[:customer]
    assert_not params.key?(:customer_email)
  end

  test "rejects a non-monthly or live recurring product" do
    annual = monthly_product.deep_dup
    annual["default_price"]["recurring"]["interval"] = "year"
    live = monthly_product.deep_dup
    live["livemode"] = true

    [ annual, live ].each do |product|
      assert_raises(Payments::SubscriptionCheckout::ConfigurationError) do
        Payments::SubscriptionCheckout.call(
          user: @user,
          success_url: "https://example.test/success",
          cancel_url: "https://example.test/cancel",
          gateway: FakeGateway.new(product: product)
        )
      end
    end
    assert_empty @user.user_subscriptions
  end

  test "does not create a second current subscription" do
    subscription = @user.user_subscriptions.create!(
      status: "active",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_subscription_id: "sub_existing",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )

    error = assert_raises(Payments::SubscriptionCheckout::AlreadySubscribed) { start_checkout }

    assert_match(/already has a subscription/, error.message)
    assert_equal [ subscription ], @user.user_subscriptions.to_a
    assert_empty @gateway.created_sessions
  end

  private

  def start_checkout
    Payments::SubscriptionCheckout.call(
      user: @user,
      success_url: "https://example.test/settings?subscription=success",
      cancel_url: "https://example.test/settings?subscription=canceled",
      gateway: @gateway
    )
  end

  def monthly_product
    {
      "id" => UserSubscription::PRODUCT_ID,
      "active" => true,
      "livemode" => false,
      "default_price" => {
        "id" => "price_monthly",
        "active" => true,
        "type" => "recurring",
        "currency" => "dkk",
        "unit_amount" => 9900,
        "recurring" => { "interval" => "month", "interval_count" => 1 }
      }
    }
  end
end
