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

  def event_payload(id:, type:, object_id:)
    JSON.generate({ id: id, object: "event", type: type, data: { object: { id: object_id } } })
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
