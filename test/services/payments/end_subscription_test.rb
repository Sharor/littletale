# frozen_string_literal: true

require "test_helper"

class Payments::EndSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "basic", admin: false, stripe_customer_id: "cus_end")
    @subscription = @user.user_subscriptions.create!(
      status: "active",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_subscription_id: "sub_end",
      stripe_customer_id: "cus_end",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  test "rejects deletion for a foreign Stripe customer" do
    object = {
      "id" => "sub_end",
      "status" => "canceled",
      "livemode" => false,
      "customer" => "cus_foreign",
      "ended_at" => Time.current.to_i,
      "items" => {
        "data" => [ { "price" => { "id" => "price_monthly", "product" => UserSubscription::PRODUCT_ID } } ]
      }
    }

    assert_raises(Payments::EndSubscription::InvalidSubscription) do
      Payments::EndSubscription.call(subscription: object)
    end

    assert_equal "active", @subscription.reload.status
  end
end
