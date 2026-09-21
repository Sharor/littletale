# frozen_string_literal: true

require "test_helper"

class Payments::LinkSubscriptionCheckoutTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false, stripe_customer_id: nil)
    @subscription = @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_checkout_session_id: "cs_subscription_link",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
  end

  test "links the Stripe customer and subscription without granting allowance" do
    assert_no_difference [ -> { BookCredit.count }, -> { CharacterCredit.count } ] do
      2.times { assert Payments::LinkSubscriptionCheckout.call(session: subscription_session) }
    end

    assert_equal "sub_linked", @subscription.reload.stripe_subscription_id
    assert_equal "cus_linked", @subscription.stripe_customer_id
    assert_equal "cus_linked", @user.reload.stripe_customer_id
    assert_equal "pending", @subscription.status
  end

  test "rejects a Checkout session for a foreign user product or customer" do
    foreign_user = subscription_session.deep_dup
    foreign_user["metadata"]["user_id"] = users(:two).id.to_s
    foreign_product = subscription_session.deep_dup
    foreign_product.dig("line_items", "data", 0, "price")["product"] = "prod_foreign"
    @user.update!(stripe_customer_id: "cus_expected")
    foreign_customer = subscription_session.merge("customer" => "cus_foreign")

    [ foreign_user, foreign_product, foreign_customer ].each do |session|
      assert_raises(Payments::LinkSubscriptionCheckout::InvalidSession) do
        Payments::LinkSubscriptionCheckout.call(session: session)
      end
    end
    assert_nil @subscription.reload.stripe_subscription_id
  end

  private

  def subscription_session
    {
      "id" => "cs_subscription_link",
      "mode" => "subscription",
      "livemode" => false,
      "customer" => "cus_linked",
      "subscription" => "sub_linked",
      "metadata" => {
        "user_subscription_id" => @subscription.id.to_s,
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
end
