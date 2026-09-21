# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BillingPortalControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "basic", admin: false, stripe_customer_id: "cus_portal_controller")
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "a subscriber can open Stripe billing management" do
    arguments = nil

    Payments::BillingPortal.stub :call, ->(**received) { arguments = received; "https://billing.stripe.test/manage" } do
      post settings_billing_portal_url
    end

    assert_redirected_to "https://billing.stripe.test/manage"
    assert_equal @user, arguments.fetch(:user)
    assert_equal settings_url, arguments.fetch(:return_url)
  end

  test "billing management requires authentication" do
    sign_out @user

    post settings_billing_portal_url

    assert_redirected_to new_user_session_url
  end
end
