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

  test "the book wizard keeps its step and unfinished story after a refresh" do
    visit new_book_url
    page.execute_script("localStorage.clear()")
    refresh

    assert_selector "[data-step='reader']:not([hidden])"
    select "English", from: "book_language"
    fill_in "book_reader_age", with: "7"
    fill_in "book_total_pages", with: "3"
    click_button "Story"
    fill_in "book_name", with: "The moonlit map"
    fill_in "book_plot", with: "Two friends follow a silver trail through the forest."
    click_button "Font"
    find("label[for='book_book_font_inter']").click

    saved_draft = JSON.parse(page.evaluate_script("localStorage.getItem('little-stories:book-wizard:#{users(:one).id}:v1')"))
    assert_equal [ "inter" ], saved_draft.dig("fields", "book[book_font]")

    refresh

    assert_selector "[data-step='font']:not([hidden])"
    assert_field "book_book_font_inter", checked: true, visible: :all
    assert_field "book_name", with: "The moonlit map", visible: :all
    assert_field "book_plot", with: "Two friends follow a silver trail through the forest.", visible: :all

    refresh
    assert_selector "[data-step='font']:not([hidden])"
    assert_field "book_name", with: "The moonlit map", visible: :all
    assert_field "book_plot", with: "Two friends follow a silver trail through the forest.", visible: :all

    [ 375, 1440 ].each do |width|
      page.current_window.resize_to(width, 1000)
      assert_selector ".book-wizard-nav"
      assert_selector "[data-step='font']:not([hidden])"
      page.save_screenshot(Rails.root.join("tmp/screenshots/book-wizard-font-#{width}.png"))
    end
  ensure
    page.execute_script("localStorage.clear()") if page.current_url
  end

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
