# frozen_string_literal: true

require "test_helper"

class Payments::BillingPortalTest < ActiveSupport::TestCase
  class FakeGateway
    attr_reader :parameters

    def create_billing_portal_session(parameters)
      @parameters = parameters
      { "url" => "https://billing.stripe.test/session" }
    end
  end

  setup do
    @user = users(:one)
    @user.update!(tier: "basic", admin: false, stripe_customer_id: "cus_portal")
    @subscription = @user.user_subscriptions.create!(
      status: "active",
      product_id: UserSubscription::PRODUCT_ID,
      price_id: "price_monthly",
      stripe_subscription_id: "sub_portal",
      stripe_customer_id: "cus_portal",
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
    @gateway = FakeGateway.new
  end

  test "creates a portal session for the current subscription customer" do
    url = Payments::BillingPortal.call(
      user: @user,
      return_url: "https://example.test/settings",
      gateway: @gateway
    )

    assert_equal "https://billing.stripe.test/session", url
    assert_equal({ customer: "cus_portal", return_url: "https://example.test/settings" }, @gateway.parameters)
  end

  test "rejects a user without a current subscription or matching customer" do
    @subscription.update!(status: "canceled")
    assert_raises(Payments::BillingPortal::Unavailable) do
      Payments::BillingPortal.call(user: @user, return_url: "https://example.test/settings", gateway: @gateway)
    end

    @subscription.update!(status: "active")
    @user.update!(stripe_customer_id: "cus_other")
    assert_raises(Payments::BillingPortal::Unavailable) do
      Payments::BillingPortal.call(user: @user, return_url: "https://example.test/settings", gateway: @gateway)
    end
  end
end
