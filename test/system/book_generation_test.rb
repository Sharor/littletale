require "application_system_test_case"
require "warden/test/helpers"

class BookGenerationTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    users(:one).tutorial.update!(terms: true)
    login_as users(:one), scope: :user
  end

  teardown { Warden.test_reset! }

  test "the castle stays visible until the illustrated book is ready" do
    book = users(:one).books.create!(name: "Castle adventure", total_pages: 1)

    [375, 1440].each do |width|
      page.current_window.resize_to(width, 1000)
      visit book_url(book)
      assert_selector "#castle_construction.lvl-1"
      assert_text I18n.t("books.status.getting_ready")
      page.save_screenshot(Rails.root.join("tmp/screenshots/castle-pending-#{width}.png"))
    end

    book.update!(generation_status: :in_progress)
    visit book_url(book)
    assert_selector "#castle_construction.lvl-1"
    assert_no_selector "#storybook"

    story_page = book.pages.create!(text: "A castle in the clouds.")
    visit book_url(book)
    assert_selector "#castle_construction.lvl-6"
    assert_no_selector "#storybook"

    illustration = Illustration.new(page: story_page)
    File.open(file_fixture("character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    book.update!(generation_status: :completed)
    visit book_url(book)
    assert_no_selector "#castle_construction"
    assert_selector "#storybook"
  end
end
