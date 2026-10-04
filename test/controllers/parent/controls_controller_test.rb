# frozen_string_literal: true

require "test_helper"

class Parent::ControlsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    sign_in @user
    post parent_session_url, params: { pin: "4826" }
  end

  test "approval mode can be selected without a subscription" do
    patch parent_control_url, params: { parent_control: { mode: "approval_required", daily_book_limit: 3 } }

    assert_redirected_to parent_url
    assert_equal "approval_required", @control.reload.mode
  end

  test "daily mode requires an active subscription" do
    patch parent_control_url, params: { parent_control: { mode: "daily_limit", daily_book_limit: 3 } }

    assert_response :unprocessable_content
    assert_equal "approval_required", @control.reload.mode
    assert_select "[role='alert']", text: /active subscription/
  end

  test "daily mode saves a positive limit for a subscriber" do
    @user.user_subscriptions.create!(status: "active", product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid)

    patch parent_control_url, params: { parent_control: { mode: "daily_limit", daily_book_limit: 3 } }

    assert_redirected_to parent_url
    assert_equal "daily_limit", @control.reload.mode
    assert_equal 3, @control.daily_book_limit
  end

  test "an administrator can select daily mode without a subscription" do
    @user.update!(admin: true)

    patch parent_control_url, params: { parent_control: { mode: "daily_limit", daily_book_limit: 3 } }

    assert_redirected_to parent_url
    assert_equal "daily_limit", @control.reload.mode

    get parent_url
    assert_select "input[name='parent_control[mode]'][value='daily_limit'][disabled]", count: 0
  end

  test "dashboard offers an explicit time zone for the daily reset" do
    get parent_url

    assert_response :success
    assert_select "select[name='parent_control[time_zone]'] option[value='UTC']"
  end

  test "an ended subscription clearly falls back to approval mode" do
    @control.update_column(:mode, "daily_limit")

    get parent_url

    assert_response :success
    assert_select "[data-effective-parent-mode='approval_required']", text: /subscription.*approval/i
    assert_select "input[name='parent_control[mode]'][value='approval_required'][checked]"
  end

  test "parent authentication is required to change rules" do
    delete parent_session_url

    patch parent_control_url, params: { parent_control: { mode: "approval_required", daily_book_limit: 2 } }

    assert_redirected_to new_parent_session_url
  end
end
