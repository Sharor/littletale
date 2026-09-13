require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard is admin only and links to duties" do
    get "/admin"
    assert_response :forbidden
    sign_in users(:one)
    get "/admin"
    assert_response :forbidden
    sign_out users(:one)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin
    get "/admin"
    assert_response :success
    assert_select "h1", "Administration"
    %w[/admin/character_image_assessments /admin/failed_books /jobs /console].each do |path|
      assert_select "a[href='#{path}']"
    end
  end
end
