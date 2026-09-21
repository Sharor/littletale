# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "a user can start monthly subscription Checkout from settings" do
    @user.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)
    subscription = @user.user_subscriptions.create!(
      status: "pending",
      product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid,
      livemode: false
    )
    result = Payments::SubscriptionCheckout::Result.new(
      subscription: subscription,
      url: "https://checkout.stripe.test/subscribe"
    )
    checkout_arguments = nil

    Payments::SubscriptionCheckout.stub :call, ->(**arguments) { checkout_arguments = arguments; result } do
      post settings_subscription_url
    end

    assert_redirected_to "https://checkout.stripe.test/subscribe"
    assert_equal @user, checkout_arguments.fetch(:user)
    assert_equal settings_url(subscription: "success"), checkout_arguments.fetch(:success_url)
    assert_equal settings_url(subscription: "canceled"), checkout_arguments.fetch(:cancel_url)
  end

  test "subscription Checkout requires authentication" do
    sign_out @user

    post settings_subscription_url

    assert_redirected_to new_user_session_url
  end

  test "an existing subscription redirects back to settings" do
    Payments::SubscriptionCheckout.stub :call,
      ->(**) { raise Payments::SubscriptionCheckout::AlreadySubscribed, "already subscribed" } do
      post settings_subscription_url
    end

    assert_redirected_to settings_url
    assert_equal "Your subscription is already active.", flash[:notice]
  end
end
