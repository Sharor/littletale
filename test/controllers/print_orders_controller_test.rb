# frozen_string_literal: true

require "test_helper"

class PrintOrdersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @admin.tutorial.update!(terms: true)
    sign_in @admin
  end

  test "enabled admins can open orders from navigation" do
    with_lulu_orders_enabled do
      get "/orders"

      assert_response :success
      assert_select "main h1", "Book orders"
      assert_select "aside nav a[href='/orders']", text: /Orders/
      assert_select "header nav a[href='/orders'][aria-label='Orders']"
    end
  end

  test "enabled ordinary users cannot see or open orders" do
    @admin.update!(admin: false)

    with_lulu_orders_enabled do
      get "/orders"
      assert_response :not_found

      get books_path
      assert_response :success
      assert_select "a[href='/orders']", count: 0
    end
  end

  test "disabled orders are hidden and inaccessible to admins" do
    without_lulu_orders_enabled do
      get "/orders"
      assert_response :not_found

      get books_path
      assert_response :success
      assert_select "a[href='/orders']", count: 0
    end
  end

  test "enabled orders still require authentication" do
    sign_out @admin

    with_lulu_orders_enabled do
      get "/orders"

      assert_redirected_to new_user_session_path
    end
  end

  private

  def with_lulu_orders_enabled
    previous = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    yield
  ensure
    ENV["LULU_ORDERS_ENABLED"] = previous
  end

  def without_lulu_orders_enabled
    previous = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "false"
    yield
  ensure
    ENV["LULU_ORDERS_ENABLED"] = previous
  end
end
