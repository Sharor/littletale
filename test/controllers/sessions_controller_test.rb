# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the primary sign-in screen offers Google and Microsoft authentication" do
    with_microsoft_oauth_configured { get new_user_session_url }

    assert_response :success
    assert_select "main[aria-labelledby='sign-in-title']", count: 1 do
      assert_select "h1#sign-in-title", "Welcome back!"
    end
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}'][method='post']"
    assert_select "button", "Continue with Google"
    assert_select "form[action='#{user_microsoft_v2_auth_omniauth_authorize_path}'][method='post']"
    assert_select "button", "Continue with Microsoft"
  end

  test "the primary sign-in screen hides Microsoft when OAuth is not configured" do
    without_microsoft_oauth_configured { get new_user_session_url }

    assert_response :success
    assert_select "form[action='#{user_microsoft_v2_auth_omniauth_authorize_path}']", count: 0
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
