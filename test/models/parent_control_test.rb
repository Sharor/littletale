# frozen_string_literal: true

require "test_helper"

class ParentControlTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "stores a secure numeric pin" do
    control = @user.build_parent_control(enabled: true, mode: "approval_required", pin: "4826",
      pin_confirmation: "4826")

    assert control.save
    assert control.authenticate_pin("4826")
    assert_not control.authenticate_pin("1111")
    assert_not_equal "4826", control.pin_digest
  end

  test "rejects a short or nonnumeric pin" do
    short = @user.build_parent_control(enabled: true, pin: "123", pin_confirmation: "123")
    assert_not short.valid?
    assert_includes short.errors[:pin], "must be 4 to 8 digits"

    letters = @user.build_parent_control(enabled: true, pin: "abcd", pin_confirmation: "abcd")
    assert_not letters.valid?
    assert_includes letters.errors[:pin], "must be 4 to 8 digits"
  end

  test "daily allowance falls back to approval when the subscription is not active" do
    control = @user.create_parent_control!(enabled: true, mode: "daily_limit", daily_book_limit: 2,
      pin: "4826", pin_confirmation: "4826")

    assert_equal "approval_required", control.effective_mode

    @user.user_subscriptions.create!(status: "active", product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid)

    assert_equal "daily_limit", control.reload.effective_mode
  end

  test "an administrator can use subscription features without a subscription" do
    @user.update!(admin: true)
    control = @user.create_parent_control!(enabled: true, mode: "daily_limit", daily_book_limit: 2,
      pin: "4826", pin_confirmation: "4826")

    assert_predicate control, :subscription_features_available?
    assert_equal "daily_limit", control.effective_mode
  end

  test "daily limit must be positive" do
    control = @user.build_parent_control(enabled: true, mode: "daily_limit", daily_book_limit: 0,
      pin: "4826", pin_confirmation: "4826")

    assert_not control.valid?
    assert_includes control.errors[:daily_book_limit], "must be greater than 0"
  end

  test "five incorrect pin attempts temporarily lock access" do
    control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")

    5.times { assert_not control.authenticate_access_pin("1111") }

    assert control.reload.pin_locked?
    assert_not control.authenticate_access_pin("4826")
  end

  test "a correct pin clears earlier failures" do
    control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    2.times { control.authenticate_access_pin("1111") }

    assert control.authenticate_access_pin("4826")
    assert_equal 0, control.reload.failed_pin_attempts
    assert_nil control.locked_until
  end
end
