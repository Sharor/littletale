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

  test "a signed-in user can accept the agreements and continue to the library" do
    visit eula_url
    assert_text I18n.t("activerecord.attributes.tutorial.eula")

    click_on I18n.t("activerecord.attributes.tutorial.accept")
    assert_text I18n.t("activerecord.attributes.tutorial.terms")

    click_on I18n.t("activerecord.attributes.tutorial.accept")
    assert_current_path books_path
    assert_predicate Tutorial.find_by!(user: users(:one)), :terms?
  end
end
