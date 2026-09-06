# frozen_string_literal: true

require "test_helper"

class Admin::FailedBooksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "forbids guests and non-administrators" do
    get admin_failed_books_url
    assert_response :forbidden

    sign_in users(:one)
    get admin_failed_books_url
    assert_response :forbidden
  end

  test "lists failed books and their persisted investigation metadata for administrators" do
    book = Book.create!(user: users(:one), name: "Blocked book", total_pages: 1)
    book.update!(
      generation_status: :failed,
      generation_failed_at: Time.current,
      generation_failure: { "message" => "Rejected by the safety system", "request_id" => "req_blocked" }
    )
    admin = users(:three)
    admin.update!(email: User::ADMINS.first)
    sign_in admin

    get admin_failed_books_url

    assert_response :success
    assert_select "h1", "Failed book generations"
    assert_select "h2", "Blocked book"
    assert_select "pre", /req_blocked/
  end
end
