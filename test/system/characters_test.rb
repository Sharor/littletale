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

  test "book action follows whether characters are selected" do
    character = characters(:hernandes)
    visit characters_url

    assert_button "Make a book without characters"
    find("#character_#{character.id} .fable-character-card").click
    assert_button "Make a book with these characters"
    page.current_window.resize_to(375, 900)
    find("#character_#{character.id} .fable-character-card").click
    assert_button "Make a book without characters"
  end

  test "delete dialog can be cancelled then confirmed without leaving the character list" do
    character = characters(:hernandes)
    page.current_window.resize_to(1440, 1000)
    visit characters_url
    find("a[aria-label=\"Delete #{character.name}\"]").click
    assert_current_path characters_path
    assert_selector "[role='dialog']", text: character.name
    page.save_screenshot(Rails.root.join("tmp/screenshots/character-delete-desktop.png"))
    click_on "Cancel"
    assert_no_selector "[role='dialog']"
    assert_selector "#character_#{character.id}"

    find("a[aria-label=\"Delete #{character.name}\"]").click
    within "[role='dialog']" do
      find("button[aria-label='Close']").click
    end
    assert_no_selector "[role='dialog']"

    page.current_window.resize_to(375, 900)
    find("a[aria-label=\"Delete #{character.name}\"]").click
    assert_selector "dialog[open]"
    page.save_screenshot(Rails.root.join("tmp/screenshots/character-delete-mobile.png"))
    page.send_keys :escape
    assert_no_selector "[role='dialog']"
    find("a[aria-label=\"Delete #{character.name}\"]").click
    within "[role='dialog']" do
      click_on "Delete", exact: true
    end
    assert_no_selector "[role='dialog']"
    assert_no_selector "#character_#{character.id}"
    assert_current_path characters_path
    assert_not_nil character.reload.deleted_at
  end

end
