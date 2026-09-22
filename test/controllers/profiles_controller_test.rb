# frozen_string_literal: true

require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "a user without a language starts onboarding before opening the library" do
    @user.update_column(:language, nil)

    get books_url

    assert_redirected_to profile_url(onboarding: true)
  end

  test "terms remain the first step" do
    @user.update_column(:language, nil)
    @user.tutorial.update!(terms: false)

    get books_url

    assert_redirected_to terms_url
  end

  test "profile offers supported languages and an optional reader age" do
    get profile_url

    assert_response :success
    assert_select "form[action='#{profile_path}']" do
      assert_select "select[name='user[language]'] option[value='en']", "English"
      assert_select "select[name='user[language]'] option[value='da']", "Dansk"
      assert_select "input[name='user[reader_age]'][type='number']"
    end
  end

  test "onboarding uses a full-width layout without the app sidebar" do
    @user.update_column(:language, nil)

    get profile_url(onboarding: true)

    assert_response :success
    assert_select ".profile-onboarding main", count: 1
    assert_select ".profile-onboarding aside", count: 0
  end

  test "onboarding saves preferences and opens the library" do
    @user.update_column(:language, nil)

    patch profile_url, params: { onboarding: true, user: { language: "da", reader_age: "7" } }

    assert_redirected_to books_url
    assert_equal "da", @user.reload.language
    assert_equal 7, @user.reader_age
  end

  test "reader age is optional" do
    patch profile_url, params: { user: { language: "en", reader_age: "" } }

    assert_redirected_to profile_url
    assert_nil @user.reload.reader_age
  end

  test "confirmation uses the newly selected language" do
    @user.update!(language: "da")

    patch profile_url, params: { user: { language: "en", reader_age: "" } }
    follow_redirect!

    assert_select "body", text: /Your profile was updated\./
  end

  test "invalid preferences are rendered without being saved" do
    patch profile_url, params: { user: { language: "fr", reader_age: "200" } }

    assert_response :unprocessable_content
    assert_not_equal "fr", @user.reload.language
  end
end
