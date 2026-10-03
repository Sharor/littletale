require "application_system_test_case"

class BookHistoryTest < ApplicationSystemTestCase
  test "browser history restores a clean reader that can keep turning pages" do
    [ 375, 1440 ].each do |width|
      page.current_window.resize_to(width, 1000)
      visit "/"
      click_link "Read a sample story", match: :first
      assert_selector "#storybook .stf__wrapper", count: 1
      page_count = page.all("#storybook .page", visible: :all).size

      2.times do
        page.go_back
        assert_current_path "/"
        page.go_forward
        assert_selector "#storybook .stf__wrapper", count: 1
        assert_selector "#storybook .stf__block", count: 1
        assert_selector "#storybook .page", count: page_count, visible: :all

        # The desktop uses page clicks; the mobile controls drive the same reader.
        page.execute_script("document.getElementById('nextPage').click()")
        assert_selector "#storybook.is-flipping"
        assert_no_selector "#storybook.is-flipping", wait: 3
        assert_no_selector "#storybook.is-closed"
      end

      visible_story = page.find("#storybook .story-body", match: :first).text
      click_link "Back to sample stories"
      assert_current_path "/"
      page.go_back
      assert_selector "#storybook .stf__wrapper", count: 1
      assert_selector "#storybook .story-body", text: visible_story
      page.save_screenshot(Rails.root.join("tmp/screenshots/book-history-#{width}.png"))

      page.execute_script("document.getElementById('nextPage').click()")
      assert_selector "#storybook.is-flipping"
      click_link "Back to sample stories"
      assert_current_path "/"
      page.go_back
      assert_selector "#storybook .stf__wrapper", count: 1
      assert_no_selector "#storybook.is-flipping"
      page.execute_script("document.getElementById('prevPage').click()")
      assert_selector "#storybook.is-flipping"
      assert_no_selector "#storybook.is-flipping", wait: 3
    end
  end
end
