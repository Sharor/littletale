# frozen_string_literal: true

require "test_helper"

class TutorialsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "eula renders the EULA and keeps the tutorial pending" do
    get eula_url

    tutorial = Tutorial.find_by!(user: @user)
    assert_response :success
    assert_not tutorial.eula?
    assert_not tutorial.terms?
    assert_select "main[aria-labelledby='eula-title']", count: 1 do
      assert_select "h1#eula-title", I18n.t("activerecord.attributes.tutorial.eula")
    end
    assert_select "form[action='#{terms_path}']"
  end

  test "terms accepts the EULA and renders the terms view" do
    get terms_url

    tutorial = Tutorial.find_by!(user: @user)
    assert_response :success
    assert_predicate tutorial, :eula?
    assert_not tutorial.terms?
    assert_select "main[aria-labelledby='terms-title']", count: 1 do
      assert_select "h1#terms-title", I18n.t("activerecord.attributes.tutorial.terms")
      assert_select "h2", "Copyright complaints"
      assert_select "strong", "Governing law."
    end
    assert_select "form[action='#{accept_terms_path}'][method='post']"
  end

  test "accepting the terms records acceptance and redirects to the library" do
    post accept_terms_url

    assert_predicate Tutorial.find_by!(user: @user), :terms?
    assert_redirected_to books_url
  end

  test "tutorial accepts the terms and renders the completion step" do
    get tutorial_url

    tutorial = Tutorial.find_by!(user: @user)
    assert_response :success
    assert_predicate tutorial, :terms?
    assert_not tutorial.tutorial_complete?
    assert_select "main[aria-labelledby='tutorial-title']", count: 1 do
      assert_select "h1#tutorial-title", I18n.t("activerecord.attributes.tutorial.tutorial")
    end
    assert_select "form[action='#{tutorial_complete_path}']"
  end

  test "complete marks the tutorial complete and redirects to the app" do
    Tutorial.find_by!(user: @user).update!(terms: true)

    post tutorial_complete_url

    assert_predicate Tutorial.find_by!(user: @user), :tutorial_complete?
    assert_redirected_to authenticated_root_url
  end
end
