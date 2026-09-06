require "application_system_test_case"
require "warden/test/helpers"

class TutorialsTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:one), scope: :user
  end

  teardown do
    Warden.test_reset!
  end

  test "a signed-in user can complete the tutorial flow" do
    visit eula_url
    assert_text I18n.t("activerecord.attributes.tutorial.eula")

    click_on I18n.t("activerecord.attributes.tutorial.accept")
    assert_text I18n.t("activerecord.attributes.tutorial.terms")

    click_on I18n.t("activerecord.attributes.tutorial.accept")
    assert_text I18n.t("activerecord.attributes.tutorial.tutorial")

    click_on I18n.t("activerecord.attributes.tutorial.continue")
    assert_current_path authenticated_root_path
    assert_predicate Tutorial.find_by!(user: users(:one)), :tutorial_complete?
  end
end
