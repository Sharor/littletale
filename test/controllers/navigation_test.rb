require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free")
    @user.tutorial.update!(terms: true)
    sign_in @user
  end

  test "ordinary users have an empty settings section in desktop and mobile navigation" do
    [books_path, characters_path, new_book_path, book_path(books(:one))].each do |path|
      get path

      assert_response :success
      assert_select "aside section[aria-label='Settings']" do
        assert_select "h4", "Settings"
        assert_select "a, button, input", count: 0
      end
      assert_select "header section[aria-label='Settings']" do
        assert_select "h4", "Settings"
        assert_select "a, button, input", count: 0
      end
      assert_select "a[href='#{admin_root_path}']", count: 0
    end
  end

  test "administration is available only under settings on app and admin screens" do
    @user.update!(admin: true)

    [books_path, characters_path, book_path(books(:one)), admin_root_path].each do |path|
      get path

      assert_response :success
      assert_select "aside section[aria-label='Settings'] a[href='#{admin_root_path}']", "Administration"
      assert_select "header section[aria-label='Settings'] a[href='#{admin_root_path}']", "Administration"
      assert_select "body > p a[href='#{admin_root_path}']", count: 0
    end
  end

  test "mobile browsers receive settings navigation for both orientations" do
    @user.update!(admin: true)
    get characters_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1" }

    assert_response :success
    assert_select "aside section[aria-label='Settings'] a", "Administration"
    assert_select "header section[aria-label='Settings'] a", "Administration"
  end
end
