# frozen_string_literal: true

require "application_system_test_case"

class PublicMarketingTest < ApplicationSystemTestCase
  test "a parent can browse the responsive landing page and sample story" do
    page.current_window.resize_to(375, 900)
    visit "/"

    assert_text "Their next adventure starts with them."
    assert_selector ".landing-story-card", count: 3, visible: :all
    assert_equal page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), true
    assert_operator page.evaluate_script("document.querySelector('.landing-hero-page img').naturalWidth"), :>, 0
    page.save_screenshot(Rails.root.join("tmp/screenshots/landing-mobile.png"))
    page.execute_script("document.querySelector('#stories').scrollIntoView()")
    assert_text "Cute cartoon, colored pencil, claymation, and many more illustration styles are available"
    assert_no_selector "#art-styles"
    page.save_screenshot(Rails.root.join("tmp/screenshots/landing-samples-mobile.png"))

    click_link "Read a sample story", match: :first
    assert_selector "#storybook .page-cover-top h1", text: /Nora and the Little Lost Star/i
    assert_link "Back to sample stories", href: "/#stories"
    assert_button "Previous"
    assert_button "Next"
    assert_equal page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), true
    page.save_screenshot(Rails.root.join("tmp/screenshots/sample-mobile.png"))

    click_button "Next"
    assert_text "Nora, in her mustard-yellow pajamas", wait: 3
    assert_no_selector "#storybook.is-flipping", wait: 3
    page.save_screenshot(Rails.root.join("tmp/screenshots/sample-mobile-open.png"))

    click_link "Back to sample stories"
    assert_current_path "/"
    assert_selector "#stories"

    page.current_window.resize_to(1440, 1000)
    visit "/"

    assert_text "Their next adventure starts with them."
    assert_equal page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), true
    page.save_screenshot(Rails.root.join("tmp/screenshots/landing-desktop.png"))
    page.execute_script("document.querySelector('#stories').scrollIntoView()")
    assert_selector ".landing-sample-style-note"
    page.save_screenshot(Rails.root.join("tmp/screenshots/landing-samples-desktop.png"))

    visit "/stories/leo-and-adas-moon-garden"
    assert_selector "#storybook .page-cover-top h1", text: /Leo and Ada’s Moon Garden/i
    page.save_screenshot(Rails.root.join("tmp/screenshots/sample-desktop.png"))

    visit new_user_session_path
    assert_text "Create the story only they could star in."
    assert_equal page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"), true
    page.save_screenshot(Rails.root.join("tmp/screenshots/sign-in-desktop.png"))
  end
end
