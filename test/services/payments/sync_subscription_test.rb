# frozen_string_literal: true

require "test_helper"

class Payments::SyncSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "basic", admin: false, stripe_customer_id: "cus_sync")
    @subscription = @user.user_subscriptions.create!(
      status: "active",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_subscription_id: "sub_sync",
      stripe_customer_id: "cus_sync",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  test "syncs cancellation scheduling and the current Stripe status without granting credits" do
    object = stripe_subscription.merge("status" => "past_due", "cancel_at_period_end" => true)

    assert_no_difference [ -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      assert Payments::SyncSubscription.call(subscription: object)
    end

    assert_equal "past_due", @subscription.reload.status
    assert @subscription.cancel_at_period_end?
    assert_equal Time.zone.at(object.dig("items", "data", 0, "current_period_end")),
      @subscription.current_period_end
  end

  test "rejects a foreign product customer or environment" do
    foreign_product = stripe_subscription.deep_dup
    foreign_product.dig("items", "data", 0, "price")["product"] = "prod_foreign"
    foreign_customer = stripe_subscription.merge("customer" => "cus_foreign")
    live = stripe_subscription.merge("livemode" => true)

    [ foreign_product, foreign_customer, live ].each do |object|
      assert_raises(Payments::SyncSubscription::InvalidSubscription) do
        Payments::SyncSubscription.call(subscription: object)
      end
    end
    assert_equal "active", @subscription.reload.status
  end

  private

  def stripe_subscription
    {
      "id" => "sub_sync",
      "status" => "active",
      "livemode" => false,
      "customer" => "cus_sync",
      "cancel_at_period_end" => false,
      "items" => {
        "data" => [ {
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "price" => { "id" => "price_monthly", "product" => UserSubscription::PRODUCT_ID }
        } ]
      }
    }
  end
end
