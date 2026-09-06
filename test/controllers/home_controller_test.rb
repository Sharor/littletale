# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the public landing page directs visitors to sign in" do
    get "/"

    assert_response :success
    assert_select "h1", /Turn your child into a/
    assert_select "a[href='#{new_user_session_path}']", "Get Started"
    assert_select "a[href='#{new_user_session_path}']", "Create Your Story"
  end

  test "the legacy login page offers Google authentication" do
    get login_url

    assert_response :success
    assert_select "form[action='#{user_google_oauth2_omniauth_authorize_path}'][method='post']"
    assert_select "i", /Login with Google/
  end

  test "a signed-in user who has not accepted terms is redirected from login" do
    user = users(:one)
    sign_in user

    get login_url

    assert_redirected_to terms_url
  end
end
