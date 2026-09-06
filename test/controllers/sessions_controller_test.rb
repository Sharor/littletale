# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the primary sign-in screen offers Google authentication" do
    get new_user_session_url

    assert_response :success
    assert_select "h1", "Welcome back!"
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}'][method='post']"
    assert_select "button", "Continue with Google"
  end
end
