# frozen_string_literal: true

require "test_helper"

class StorySamplesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "an anonymous visitor reads a curated story in the in-app book reader" do
    get "/stories/nora-and-the-little-lost-star"

    assert_response :success
    assert_select "main.fable-reader-main[aria-label='Nora and the Little Lost Star']", count: 1 do
      assert_select "#storybook", count: 1 do
        assert_select ".page", count: 7
        assert_select ".page-cover-top h1", "Nora and the Little Lost Star"
        assert_select ".page:not(.page-cover)", count: 5
        assert_select ".page:not(.page-cover) .story-body", text: /tiny, softly glowing star/
        assert_select "img[src*='story_samples/nora-and-the-little-lost-star/page-1']", count: 1
        assert_select ".page-cover-bottom", text: /THE END/
      end
      assert_select "button#prevPage", "Previous"
      assert_select "button#nextPage", "Next"
    end
    assert_select "nav.fable-public-nav[aria-label='Main navigation']", count: 1 do
      assert_select "a[href='/#stories']", "Sample stories"
      assert_select "a[href='/#how-it-works']", "How it works"
      assert_select "a[href='/#questions']", "Questions"
      assert_select "a[href='#{new_user_session_path}']", "Sign in"
    end
    assert_select "a.sample-back-link[href='/#stories']", "Back to sample stories"
    assert_select "html[lang='en']"
    assert_select "title", "Nora and the Little Lost Star | LittleStories"
    assert_select "meta[name='description'][content*='five-page sample story']"
    assert_select "meta[property='og:title'][content='Nora and the Little Lost Star']"
  end

  test "public samples remain available to a signed-in user before onboarding" do
    sign_in users(:one)

    get "/stories/sami-and-the-fort-for-two"

    assert_response :success
    assert_select ".page-cover-top h1", "Sami and the Fort for Two"
  end

  test "all five pages are embedded in story order for client-side page turning" do
    get "/stories/leo-and-adas-moon-garden"

    assert_response :success
    page_texts = css_select("#storybook .page:not(.page-cover) .story-body").map { |node| node.text.squish }
    assert_equal StorySample.find("leo-and-adas-moon-garden").pages.map(&:text), page_texts
    assert_select ".page-footer", text: "1"
    assert_select ".page-footer", text: "5"
    assert_select ".book-back-button[href='#{new_user_session_path}']", "Create your child’s story"
  end

  test "an unknown story is not found" do
    get "/stories/not-a-story"
    assert_response :not_found

    get "/stories/6"
    assert_response :not_found
  end
end
