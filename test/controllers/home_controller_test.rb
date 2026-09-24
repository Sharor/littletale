# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the public landing page directs visitors to sign in" do
    get "/"

    assert_response :success
    assert_select "main[aria-labelledby='landing-title']", count: 1 do
      assert_select "h1#landing-title", /Turn your child into a/
    end
    assert_select "a[href='#{new_user_session_path}']", "Get Started"
    assert_select "a[href='#{new_user_session_path}']", "Create Your Story"
  end

  test "the legacy login page offers Google and Microsoft authentication" do
    with_microsoft_oauth_configured { get login_url }

    assert_response :success
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}'][method='post']"
    assert_select "form[action='#{user_microsoft_v2_auth_omniauth_authorize_path}'][method='post']"
    assert_select "main[aria-labelledby='login-title']", count: 1 do
      assert_select "h1#login-title", "Only your fantasy"
      assert_select "button", /Login with Google/
      assert_select "button", /Login with Microsoft/
    end
  end

  test "the legacy login page hides Microsoft when OAuth is not configured" do
    without_microsoft_oauth_configured { get login_url }

    assert_response :success
    assert_select "form[action='#{user_microsoft_v2_auth_omniauth_authorize_path}']", count: 0
  end

  test "a signed-in user who has not accepted terms is redirected from login" do
    user = users(:one)
    sign_in user

    get login_url

    assert_redirected_to terms_url
  end

  private

  def with_microsoft_oauth_configured
    previous_config = Devise.omniauth_configs[:microsoft_v2_auth]
    Devise.omniauth_configs[:microsoft_v2_auth] = Object.new
    yield
  ensure
    if previous_config
      Devise.omniauth_configs[:microsoft_v2_auth] = previous_config
    else
      Devise.omniauth_configs.delete(:microsoft_v2_auth)
    end
  end

  def without_microsoft_oauth_configured
    previous_config = Devise.omniauth_configs.delete(:microsoft_v2_auth)
    yield
  ensure
    Devise.omniauth_configs[:microsoft_v2_auth] = previous_config if previous_config
  end
end
