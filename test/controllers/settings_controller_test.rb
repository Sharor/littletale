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

  test "settings shows a Basic user's book credits and payment options without exposing character balance" do
    grant_paid_bundle

    get settings_url

    assert_response :success
    assert_select "[data-book-credits='1']", text: /1 book credit/
    assert_select "form[action='#{settings_book_purchase_path}'] button", text: /Buy one book credit/
    assert_select "[data-character-credits]", count: 0
    assert_select "p", text: /five character generations/i
  end

  test "a payment-required settings visit shows purchase options" do
    @user.update!(tier: "basic")

    get settings_url(payment_required: "book")

    assert_response :success
    assert_select "[role='dialog'][aria-modal='true']" do
      assert_select "h2", text: /book credit/i
      assert_select "form[action='#{settings_book_purchase_path}']"
      assert_select "button[disabled]", text: /Subscriptions coming soon/
    end
  end

  private

  def grant_paid_bundle
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_settings", payment_intent_id: "pi_settings",
      stripe_customer_id: "cus_settings", price_id: "price_settings", amount_total: 2500, currency: "dkk")
    sign_in @user.reload
  end
end
