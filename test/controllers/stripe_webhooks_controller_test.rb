# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = "whsec_test_only"
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @purchase = @user.book_purchases.create!(
      status: "pending",
      product_id: BookPurchase::PRODUCT_ID,
      price_id: "price_book_test",
      stripe_checkout_session_id: "cs_webhook_paid",
      idempotency_key: SecureRandom.uuid,
      amount_total: 2500,
      currency: "dkk",
      livemode: false
    )
  end

  test "a signed completed event fulfills once even when Stripe redelivers it" do
    gateway = gateway_returning(paid_session)
    payload = event_payload(id: "evt_paid", type: "checkout.session.completed", object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway do
        2.times { post_signed(payload) }
      end
    end

    assert_response :success
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_paid").count
    assert_equal 1, @user.reload.available_book_credits
    assert_equal 5, @user.available_character_credits
    assert_equal "basic", @user.tier
  end

  test "different event IDs for the same Checkout outcome remain idempotent" do
    gateway = gateway_returning(paid_session)
    first = event_payload(id: "evt_duplicate_a", type: "checkout.session.completed",
      object_id: "cs_webhook_paid")
    second = event_payload(id: "evt_duplicate_b", type: "checkout.session.completed",
      object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway do
        post_signed(first)
        post_signed(second)
      end
    end

    assert_response :success
    assert_equal 1, StripeEvent.where(event_type: "checkout.session.completed",
      stripe_object_id: "cs_webhook_paid").count
    assert_equal 1, @user.reload.available_book_credits
  end

  test "an invalid signature grants nothing" do
    payload = event_payload(id: "evt_forged", type: "checkout.session.completed", object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, @secret do
      post stripe_webhook_url, params: payload, headers: {
        "CONTENT_TYPE" => "application/json",
        "Stripe-Signature" => "t=1,v1=forged"
      }
    end

    assert_response :bad_request
    assert_equal 0, @user.book_credits.count
    assert_equal 0, StripeEvent.count
  end

  test "a missing webhook secret rejects the request without exposing configuration" do
    payload = event_payload(id: "evt_unconfigured", type: "checkout.session.completed",
      object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, nil do
      post stripe_webhook_url, params: payload, headers: {
        "CONTENT_TYPE" => "application/json",
        "Stripe-Signature" => "t=1,v1=anything"
      }
    end

    assert_response :bad_request
    assert_equal 0, @user.book_credits.count
  end

  test "a signed failed event records failure without granting credits" do
    payload = event_payload(id: "evt_failed", type: "checkout.session.async_payment_failed",
      object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, @secret do
      post_signed(payload)
    end

    assert_response :success
    assert_equal "failed", @purchase.reload.status
    assert_equal 0, @user.book_credits.count
    assert_equal 1, StripeEvent.where(stripe_event_id: "evt_failed").count
  end

  test "an unpaid completed event stays pending until asynchronous payment succeeds" do
    completed = event_payload(id: "evt_delayed_completed", type: "checkout.session.completed",
      object_id: "cs_webhook_paid")
    succeeded = event_payload(id: "evt_delayed_succeeded", type: "checkout.session.async_payment_succeeded",
      object_id: "cs_webhook_paid")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway_returning(paid_session.merge("payment_status" => "unpaid")) do
        post_signed(completed)
      end
    end

    assert_response :success
    assert_equal "pending", @purchase.reload.status
    assert_equal 0, @user.book_credits.count
    assert StripeEvent.exists?(stripe_event_id: "evt_delayed_completed")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway_returning(paid_session) do
        post_signed(succeeded)
      end
    end

    assert_response :success
    assert_equal "paid", @purchase.reload.status
    assert_equal 1, @user.reload.available_book_credits
  end

  test "a paid subscription invoice grants one hidden monthly allowance" do
    subscription = pending_subscription
    subscription.update!(stripe_subscription_id: "sub_webhook",
      stripe_customer_id: "cus_webhook_subscription")
    @user.update!(stripe_customer_id: "cus_webhook_subscription")
    invoice = subscription_invoice(subscription)
    gateway = gateway_returning_invoice(invoice)
    payload = event_payload(id: "evt_invoice_paid", type: "invoice.paid", object_id: invoice.fetch("id"))

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway do
        2.times { post_signed(payload) }
      end
    end

    assert_response :success
    assert_equal 1, subscription.reload.subscription_periods.count
    assert_equal 50, @user.book_credits.monthly_allowance.available.count
    assert_equal 150, @user.character_credits.monthly_allowance.available.count
    assert_equal 0, @user.available_book_credits
    assert_equal 0, @user.available_character_credits
  end

  test "a subscription Checkout completion waits for its paid invoice" do
    subscription = pending_subscription
    session = subscription_checkout_session(subscription)
    payload = event_payload(id: "evt_subscription_checkout", type: "checkout.session.completed",
      object_id: "cs_subscription_webhook")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway_returning(session) do
        post_signed(payload)
      end
    end

    assert_response :success
    assert_equal "sub_webhook", subscription.reload.stripe_subscription_id
    assert_equal "cus_webhook_subscription", subscription.stripe_customer_id
    assert_equal "pending", @purchase.reload.status
    assert_empty @user.book_credits
  end

  test "a deleted subscription saves the remaining allowance into the visible pool" do
    subscription = pending_subscription
    subscription.activate_period!(
      stripe_subscription_id: "sub_webhook",
      stripe_invoice_id: "in_initial",
      stripe_customer_id: "cus_webhook_subscription",
      price_id: "price_monthly",
      period_start: 1.month.ago,
      period_end: Time.current
    )
    @user.book_credits.monthly_allowance.limit(42).update_all(status: "consumed")
    @user.character_credits.monthly_allowance.limit(132).update_all(status: "consumed")
    object = {
      id: "sub_webhook",
      livemode: false,
      status: "canceled",
      customer: "cus_webhook_subscription",
      ended_at: Time.current.to_i,
      items: { data: [ { price: { id: "price_monthly", product: UserSubscription::PRODUCT_ID } } ] }
    }
    payload = event_payload(id: "evt_subscription_deleted", type: "customer.subscription.deleted",
      object_id: "sub_webhook", object: object)

    Payments::Config.stub :webhook_secret, @secret do
      post_signed(payload)
    end

    assert_response :success
    assert_equal "canceled", subscription.reload.status
    assert_equal 8, @user.reload.available_book_credits
    assert_equal 18, @user.available_character_credits
  end

  test "subscription updates for the same Stripe object are each synchronized" do
    subscription = pending_subscription
    subscription.update!(
      status: "active",
      stripe_subscription_id: "sub_webhook",
      stripe_customer_id: "cus_webhook_subscription"
    )
    active = stripe_subscription_object(status: "active", cancel_at_period_end: false)
    canceling = stripe_subscription_object(status: "active", cancel_at_period_end: true)
    gateway = gateway_returning_subscriptions(active, canceling)
    first = event_payload(id: "evt_subscription_update_a", type: "customer.subscription.updated",
      object_id: "sub_webhook")
    second = event_payload(id: "evt_subscription_update_b", type: "customer.subscription.updated",
      object_id: "sub_webhook")

    Payments::Config.stub :webhook_secret, @secret do
      Payments::StripeGateway.stub :new, gateway do
        post_signed(first)
        post_signed(second)
      end
    end

    assert_response :success
    assert subscription.reload.cancel_at_period_end?
    assert_equal 2, StripeEvent.where(event_type: "customer.subscription.updated",
      stripe_object_id: "sub_webhook").count
  end

  test "an expired subscription Checkout can be retried" do
    subscription = pending_subscription
    payload = event_payload(id: "evt_subscription_expired", type: "checkout.session.expired",
      object_id: "cs_subscription_webhook")

    Payments::Config.stub :webhook_secret, @secret do
      post_signed(payload)
    end

    assert_response :success
    assert_equal "incomplete_expired", subscription.reload.status
    assert_equal "checkout.session.expired", subscription.failure_reason
  end

  private

  def gateway_returning(session)
    transaction_depth = BookPurchase.connection.open_transactions
    Object.new.tap do |gateway|
      gateway.define_singleton_method(:retrieve_checkout_session) do |_id|
        if BookPurchase.connection.open_transactions > transaction_depth
          raise "Stripe retrieval must happen before the webhook database transaction"
        end

        session
      end
    end
  end

  def gateway_returning_invoice(invoice)
    transaction_depth = BookPurchase.connection.open_transactions
    Object.new.tap do |gateway|
      gateway.define_singleton_method(:retrieve_invoice) do |_id|
        if BookPurchase.connection.open_transactions > transaction_depth
          raise "Stripe retrieval must happen before the webhook database transaction"
        end

        invoice
      end
    end
  end

  def gateway_returning_subscriptions(*subscriptions)
    Object.new.tap do |gateway|
      gateway.define_singleton_method(:retrieve_subscription) { |_id| subscriptions.shift }
    end
  end

  def stripe_subscription_object(status:, cancel_at_period_end:)
    {
      "id" => "sub_webhook",
      "status" => status,
      "livemode" => false,
      "customer" => "cus_webhook_subscription",
      "cancel_at_period_end" => cancel_at_period_end,
      "items" => {
        "data" => [ {
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "price" => { "id" => "price_monthly", "product" => UserSubscription::PRODUCT_ID }
        } ]
      }
    }
  end

  def pending_subscription
    @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_checkout_session_id: "cs_subscription_webhook",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  def subscription_invoice(subscription)
    {
      "id" => "in_webhook",
      "status" => "paid",
      "livemode" => false,
      "customer" => "cus_webhook_subscription",
      "parent" => {
        "subscription_details" => {
          "subscription" => "sub_webhook",
          "metadata" => {
            "user_subscription_id" => subscription.id.to_s,
            "user_id" => @user.id.to_s,
            "product_id" => UserSubscription::PRODUCT_ID
          }
        }
      },
      "lines" => {
        "data" => [ {
          "type" => "subscription",
          "quantity" => 1,
          "period" => { "start" => Time.current.to_i, "end" => 1.month.from_now.to_i },
          "pricing" => {
            "price_details" => { "price" => "price_monthly", "product" => UserSubscription::PRODUCT_ID }
          }
        } ]
      }
    }
  end

  def subscription_checkout_session(subscription)
    {
      "id" => "cs_subscription_webhook",
      "mode" => "subscription",
      "livemode" => false,
      "customer" => "cus_webhook_subscription",
      "subscription" => "sub_webhook",
      "metadata" => {
        "user_subscription_id" => subscription.id.to_s,
        "user_id" => @user.id.to_s,
        "product_id" => UserSubscription::PRODUCT_ID
      },
      "line_items" => {
        "data" => [ {
          "quantity" => 1,
          "price" => {
            "id" => "price_monthly",
            "product" => UserSubscription::PRODUCT_ID,
            "type" => "recurring"
          }
        } ]
      }
    }
  end

  def paid_session
    {
      "id" => "cs_webhook_paid",
      "mode" => "payment",
      "payment_status" => "paid",
      "livemode" => false,
      "amount_total" => 2500,
      "currency" => "dkk",
      "customer" => "cus_webhook",
      "payment_intent" => "pi_webhook",
      "metadata" => {
        "purchase_id" => @purchase.id.to_s,
        "user_id" => @user.id.to_s,
        "product_id" => BookPurchase::PRODUCT_ID
      },
      "line_items" => {
        "data" => [ {
          "quantity" => 1,
          "price" => { "id" => "price_book_test", "product" => BookPurchase::PRODUCT_ID, "type" => "one_time" }
        } ]
      }
    }
  end

  def event_payload(id:, type:, object_id:, object: nil)
    JSON.generate({ id: id, object: "event", type: type, data: { object: object || { id: object_id } } })
  end

  def post_signed(payload)
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, @secret)
    header = Stripe::Webhook::Signature.generate_header(timestamp, signature)
    post stripe_webhook_url, params: payload, headers: {
      "CONTENT_TYPE" => "application/json",
      "Stripe-Signature" => header
    }
  end
end
