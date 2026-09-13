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
    assert_select "h1", I18n.t("activerecord.attributes.tutorial.eula")
    assert_select "form[action='#{terms_path}']"
  end

  test "terms accepts the EULA and renders the terms view" do
    get terms_url

    tutorial = Tutorial.find_by!(user: @user)
    assert_response :success
    assert_predicate tutorial, :eula?
    assert_not tutorial.terms?
    assert_select "h1", I18n.t("activerecord.attributes.tutorial.terms")
    assert_select "form[action='#{books_path}']"
  end

  test "tutorial accepts the terms and renders the completion step" do
    get tutorial_url

    tutorial = Tutorial.find_by!(user: @user)
    assert_response :success
    assert_predicate tutorial, :terms?
    assert_not tutorial.tutorial_complete?
    assert_select "h1", I18n.t("activerecord.attributes.tutorial.tutorial")
    assert_select "form[action='#{tutorial_complete_path}']"
  end

  test "complete marks the tutorial complete and redirects to the app" do
    Tutorial.find_by!(user: @user).update!(terms: true)

    post tutorial_complete_url

    assert_predicate Tutorial.find_by!(user: @user), :tutorial_complete?
    assert_redirected_to authenticated_root_url
  end
end
