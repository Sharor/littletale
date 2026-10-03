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

  test "dashboard shows manual production health actions without running them" do
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    get admin_root_url

    assert_response :success
    assert_select "section[data-health-checks]" do
      assert_select "h2", "Production health"
      assert_select "[data-health-check='object_storage'][data-health-status='not_checked']"
      assert_select "[data-health-check='openai'][data-health-status='not_checked']"
      assert_select "[data-health-check='gemini'][data-health-status='not_checked']"
      assert_select "form[action='#{admin_health_check_path}'][method='post']"
      assert_select "form[action='#{admin_test_email_path}'][method='post']"
      assert_select "button[data-turbo-submits-with]", minimum: 2
    end
  end

  test "dashboard shows provider mode credentials failure window and switch audit" do
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin
    GenerationProviderRequest.delete_all
    GenerationProviderSetting.delete_all
    setting = GenerationProviderSetting.current.change_mode!("automatic")
    started_at = setting.automatic_window_started_at + 1.second
    2.times do |index|
      GenerationProviderRequest.create!(provider: "openai", operation: "book_story", model: "gpt-4.1",
        outcome: "availability_failure", started_at: started_at + index.seconds,
        finished_at: started_at + index.seconds + 1.second)
    end
    GenerationProviderRequest.create!(provider: "openai", operation: "book_story", model: "gpt-4.1",
      outcome: "succeeded", started_at: started_at + 3.seconds, finished_at: started_at + 4.seconds)
    setting.update!(active_provider: "gemini", switched_at: Time.zone.parse("2026-10-03 12:00:00"),
      switch_reason: "openai_availability_failures_16_of_20")

    with_env("OPENAI_ACCESS_TOKEN" => "openai-key", "GEMINI_API_KEY" => nil) do
      get admin_root_url
    end

    assert_response :success
    assert_select "section[data-generation-provider][data-provider-mode='automatic'][data-active-provider='gemini']" do
      assert_select "input[name='mode'][value='automatic'][checked]"
      assert_select "[data-provider-window]", text: /2.*3.*20/
      assert_select "[data-provider-switch-reason]", text: /16.*20/
      assert_select "[data-provider-credential='openai'][data-configured='true']"
      assert_select "[data-provider-credential='gemini'][data-configured='false']"
      assert_select "form[action='#{admin_generation_provider_path}'] input[name='_method'][value='patch']"
    end
  end

  private

  def with_env(values)
    original = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
