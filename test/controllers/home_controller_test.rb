# frozen_string_literal: true

require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the public landing page explains the product and proves it with real samples" do
    get "/"

    assert_response :success
    assert_select "main[aria-labelledby='landing-title']", count: 1 do
      assert_select "h1#landing-title", "Their next adventure starts with them."
      assert_select "#how-it-works .landing-step", count: 3
      assert_select "#questions details", minimum: 6
      assert_select "#questions", text: /uses AI to turn your characters and plot into story text and illustrations/
      assert_select "#questions", text: /English, Danish, Greek, or Spanish/
    end
    assert_select "nav.fable-public-nav[aria-label='Main navigation']", count: 1 do
      assert_select "a[href='#stories']", "Sample stories"
      assert_select "a[href='#how-it-works']", "How it works"
      assert_select "a[href='#questions']", "Questions"
      assert_select "a[href='#{new_user_session_path}']", "Sign in"
    end
    assert_select "a[href='#{new_user_session_path}']", text: "Create your child’s story", minimum: 2
    assert_select "a[href='/stories/nora-and-the-little-lost-star']", "Read this story"
    assert_select "a[href='/stories/leo-and-adas-moon-garden']", "Read this story"
    assert_select "a[href='/stories/sami-and-the-fort-for-two']", "Read this story"
    assert_select "#stories" do
      assert_select ".landing-story-card", count: 3
      assert_select ".landing-sample-style-note", "Cute cartoon, colored pencil, claymation, and many more illustration styles are available when you create your story."
    end
    assert_select "#art-styles", count: 0
    assert_select "[data-trial-terms]", text: /3 trial books.*up to 5 pages.*one month/i
    assert_select "html[lang='en']"
    assert_select "title", "Personalized stories for children | MinorTale"
    assert_select ".fable-public-brand", text: "MinorTale"
    assert_select "meta[name='description'][content*='Create an illustrated story starring your child']"
    assert_select "meta[property='og:title'][content='Their next adventure starts with them.']"
    assert_select "meta[property='og:image'][content*='story_samples/nora-and-the-little-lost-star/page-1']"
  end

  test "the landing page stays in English until the redesign copy is approved" do
    cookies[:locale] = "da"

    get "/"

    assert_response :success
    assert_select "h1#landing-title", "Their next adventure starts with them."
  end

  test "the legacy login page redirects to the primary sign-in screen" do
    get login_url

    assert_redirected_to new_user_session_url
  end

  test "a signed-in user who has not accepted terms is redirected from login" do
    user = users(:one)
    sign_in user

    get login_url

    assert_redirected_to terms_url
  end

end
