# frozen_string_literal: true

require "test_helper"

class ConsoleControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "forbids guests" do
    get "/console"

    assert_response :forbidden
  end

  test "forbids signed-in non-administrators" do
    sign_in users(:one)

    get "/console"

    assert_response :forbidden
  end

  test "allows administrators without requiring tutorial completion" do
    admin = users(:three)
    admin.update!(email: User::ADMINS.first)
    sign_in admin

    get "/console"

    assert_response :success
    assert_select "h1", "Rails Console"
    assert_select "a[href='#{admin_failed_books_path}']", "Failed book generations"
  end
end
