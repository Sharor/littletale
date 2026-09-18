# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "settings shows trial status and available books" do
    get settings_url

    assert_response :success
    assert_select "h1", "Trial & subscription"
    assert_select "[data-trial-status='not_started']", text: /Not started/
    assert_select "[data-books-remaining='3']", text: /3 books available/
  end

  test "an expired trial redirects application pages to settings and forces the subscription dialog" do
    @user.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)

    get books_url

    assert_redirected_to settings_url
    follow_redirect!
    assert_response :success
    assert_select "[role='dialog'][aria-modal='true']" do
      assert_select "h2", "Your trial has ended"
      assert_select "p", /subscribe/i
    end
  end

  test "an expired trial can still access settings and sign out" do
    @user.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)
    @user.tutorial.update!(terms: false)

    get settings_url
    assert_response :success

    delete destroy_user_session_url
    assert_response :redirect
  end

  test "an administrator can open settings directly" do
    @user.update!(admin: true)

    get settings_url

    assert_response :success
    assert_select "[data-trial-status='admin']", text: /Administrator/
  end

  test "an expired trial receives payment required for JSON requests" do
    @user.update!(trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)

    get books_url(format: :json)

    assert_response :payment_required
    assert_equal({ "error" => "trial_expired", "settings_url" => settings_url }, response.parsed_body)
  end

  test "paid users retain access after prior trial dates" do
    @user.update!(tier: "basic", trial_started_at: 2.months.ago, trial_expires_at: 1.month.ago)

    get books_url

    assert_response :success
  end
end
