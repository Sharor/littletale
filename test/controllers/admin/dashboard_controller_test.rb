require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard is admin only and links to duties" do
    get "/admin"
    assert_response :forbidden
    sign_in users(:one)
    get "/admin"
    assert_response :forbidden
    sign_out users(:one)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin
    get "/admin"
    assert_response :success
    assert_select "h1", "Administration"
    %w[/admin/character_image_assessments /admin/failed_books /jobs /console].each do |path|
      assert_select "a[href='#{path}']"
    end
    assert_select "h2", "User access"
    assert_select "tr[data-user-id='#{users(:one).id}']" do
      assert_select "td", text: users(:one).email
      assert_select "td", text: /Not started/
      assert_select "td", text: /3/
    end
  end

  test "dashboard shows Basic book and character credit balances" do
    owner = users(:one)
    owner.update!(tier: "free", admin: false)
    purchase = owner.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_admin_dashboard", payment_intent_id: "pi_admin_dashboard",
      stripe_customer_id: "cus_admin_dashboard", price_id: "price_test", amount_total: 2500, currency: "dkk")
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    get admin_root_url

    assert_response :success
    assert_select "tr[data-user-id='#{owner.id}']" do
      assert_select "td", text: /Basic/
      assert_select "[data-admin-book-credits='1']", text: /1/
      assert_select "[data-admin-character-credits='5']", text: /5/
    end
  end
end
