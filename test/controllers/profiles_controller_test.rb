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
      assert_select "select[name='user[language]'] option[value='el']", "Ελληνικά"
      assert_select "select[name='user[language]'] option[value='es']", "Español"
      assert_select "input[name='user[reader_age]'][type='number']"
      assert_select "input[name='user[parent_restricted_mode]'][type='hidden'][value='0']"
      assert_select "section.parent-restricted-setting--disabled[data-controller='parent-restriction']"
      assert_select "input.parent-restricted-switch__input[name='user[parent_restricted_mode]'][type='checkbox'][role='switch']"
      assert_select "[data-parent-restricted-explanation]", text: /daily book allowance or require approval/i
    end
  end

  test "an existing parent control puts pin confirmation in a dialog" do
    @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")

    get profile_url

    assert_response :success
    assert_select "section.parent-restricted-setting:not(.parent-restricted-setting--disabled)"
    assert_select "input.parent-restricted-switch__input[role='switch'][checked]"
    assert_select "dialog[data-parent-restriction-target='dialog']" do
      assert_select "input[name='user[current_parent_pin]'][type='password']:not([required])"
      assert_select "button[type='button'][data-action='parent-restriction#confirm']"
    end
    assert_select "section.parent-restricted-setting > input[name='user[current_parent_pin]']", count: 0
  end

  test "a disabled parent control renders a dimmed off switch" do
    @user.create_parent_control!(enabled: false, pin: "4826", pin_confirmation: "4826")

    get profile_url

    assert_response :success
    assert_select "section.parent-restricted-setting--disabled"
    assert_select "input.parent-restricted-switch__input[role='switch']:not([checked])"
    assert_select "[data-parent-restriction-target='status']", text: /Off/
  end

  test "switch labels are valid translations in every supported language" do
    User::SUPPORTED_LANGUAGES.each_key do |locale|
      assert I18n.exists?("profile.parent_control.on", locale), "missing #{locale} on label"
      assert I18n.exists?("profile.parent_control.off", locale), "missing #{locale} off label"
    end

    get profile_url

    assert_not_includes response.body, "translation_missing"
  end

  test "enabling parent restricted mode creates a secure pin" do
    assert_difference "ParentControl.count", 1 do
      patch profile_url, params: { user: { language: "en", reader_age: "7",
        parent_restricted_mode: "1", parent_pin: "4826", parent_pin_confirmation: "4826" } }
    end

    assert_redirected_to profile_url
    control = @user.reload.parent_control
    assert control.enabled?
    assert control.authenticate_pin("4826")
  end

  test "initial parent restricted setup rejects an invalid pin" do
    assert_no_difference "ParentControl.count" do
      patch profile_url, params: { user: { language: "en", reader_age: "7",
        parent_restricted_mode: "1", parent_pin: "12", parent_pin_confirmation: "12" } }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /PIN must be 4 to 8 digits/
  end

  test "disabling parent restricted mode requires the current pin" do
    control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")

    patch profile_url, params: { user: { language: "en", reader_age: "7",
      parent_restricted_mode: "0", current_parent_pin: "1111" } }

    assert_response :unprocessable_content
    assert control.reload.enabled?
    assert_select "[role='alert']", text: /PIN is incorrect/
  end

  test "the current pin can disable parent restricted mode" do
    control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")

    patch profile_url, params: { user: { language: "en", reader_age: "7",
      parent_restricted_mode: "0", current_parent_pin: "4826" } }

    assert_redirected_to profile_url
    assert_not control.reload.enabled?
  end

  test "the current pin can re-enable parent restricted mode" do
    control = @user.create_parent_control!(enabled: false, pin: "4826", pin_confirmation: "4826")

    patch profile_url, params: { user: { language: "en", reader_age: "7",
      parent_restricted_mode: "1", current_parent_pin: "4826" } }

    assert_redirected_to profile_url
    assert control.reload.enabled?
  end

  test "a locked parent pin cannot change restricted mode" do
    control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    control.update_columns(failed_pin_attempts: 5, locked_until: 10.minutes.from_now)

    patch profile_url, params: { user: { language: "en", reader_age: "7",
      parent_restricted_mode: "0", current_parent_pin: "4826" } }

    assert_response :unprocessable_content
    assert control.reload.enabled?
  end

  test "saving ordinary profile changes does not require the pin" do
    @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")

    patch profile_url, params: { user: { language: "da", reader_age: "8",
      parent_restricted_mode: "1", current_parent_pin: "" } }

    assert_redirected_to profile_url
    assert_equal "da", @user.reload.language
    assert_equal 8, @user.reader_age
    assert @user.parent_control.enabled?
  end

  test "the language placeholder is only offered before a language is chosen" do
    @user.update_column(:language, nil)

    get profile_url(onboarding: true)

    assert_select "select[name='user[language]'] option[value='']", "Choose a language"

    @user.update!(language: "en")
    get profile_url

    assert_select "select[name='user[language]'] option[value='']", count: 0
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
