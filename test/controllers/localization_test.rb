# frozen_string_literal: true

require "test_helper"

class LocalizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(language: "da")
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "the Danish preference localizes the library and shared navigation" do
    get books_url

    assert_response :success
    assert_select "main h1", "Nuværende bibliotek"
    assert_select "main", text: /Lav en ny bog/
    assert_select "aside", text: /Startside/
    assert_select "aside section[aria-label='Indstillinger']", text: /Brugerprofil/
  end

  test "the Greek preference localizes the library and shared navigation" do
    @user.update!(language: "el")

    get books_url

    assert_response :success
    assert_select "main h1", "Η βιβλιοθήκη σας"
    assert_select "main", text: /Δημιουργήστε ένα νέο βιβλίο/
    assert_select "aside", text: /Αρχική/
    assert_select "aside section[aria-label='Ρυθμίσεις']", text: /Προφίλ χρήστη/
  end

  test "the Danish preference localizes characters and account settings" do
    get characters_url
    assert_response :success
    assert_select "main h1", "Figurer"
    assert_select "main", text: /Vælg de figurer/

    get settings_url
    assert_response :success
    assert_select "main h1", "Prøveperiode og abonnement"
  end

  test "legal terms stay in English for localized users" do
    %w[da el].each do |language|
      @user.update!(language: language)
      get terms_url

      assert_response :success
      assert_select "h1#terms-title", "Terms of Use"
      assert_select "h2", "Copyright complaints"
      assert_select "strong", "Governing law."
    end
  end

  test "the selected language remains active on the sign-in screen after sign out" do
    delete destroy_user_session_url
    get new_user_session_url

    assert_response :success
    assert_select "h1", "Velkommen tilbage!"
    assert_select "main", text: /Fortsæt med Google/
  end
end
