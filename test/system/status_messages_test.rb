require "application_system_test_case"
require "warden/test/helpers"

class StatusMessagesTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    users(:one).tutorial.update!(terms: true)
    login_as users(:one), scope: :user
  end

  teardown { Warden.test_reset! }

  test "status messages do not shift the page or sidebar at phone and desktop widths" do
    [375, 1440].each do |width|
      page.current_window.resize_to(width, 1000)
      visit profile_url
      click_button I18n.t("profile.save")
      assert_text I18n.t("profile.updated")
      assert_selector "[role='status']", count: 1

      before = layout_positions
      page.save_screenshot(Rails.root.join("tmp/screenshots/status-message-#{width}.png"))
      within ".fable-flash" do
        find("button[aria-label='Close']").click
      end
      assert_equal before, layout_positions, "A status message moved the layout at #{width}px"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    end
  end

  private

  def layout_positions
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('main, .site-sidebar')).map(element => {
        const bounds = element.getBoundingClientRect();
        return [bounds.x, bounds.y, bounds.width];
      })
    JS
  end
end
