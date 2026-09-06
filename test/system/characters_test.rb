# frozen_string_literal: true

require "application_system_test_case"
require "warden/test/helpers"

class CharactersTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    users(:one).tutorial.update!(terms: true)
    login_as users(:one), scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "a user can switch from photo to descriptive character creation" do
    visit new_character_url

    assert_text "Upload Character Photo"
    click_on "Descriptive Form"
    assert_selector "#content-form:not(.hidden)"
    assert_text "Character Appearance"
  end
end
