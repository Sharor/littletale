# frozen_string_literal: true

require "test_helper"

class Admin::BooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  test "an administrator starts a new generation attempt without erasing prior failure evidence" do
    book = Book.create!(user: users(:one), name: "Blocked book", total_pages: 1)
    book.update!(
      generation_status: :failed,
      generation_failure: { "request_id" => "req_original" },
      generation_failed_at: Time.current
    )
    admin = users(:three)
    admin.update!(email: User::ADMINS.first)
    sign_in admin

    assert_enqueued_with(job: GenerateBookJob, args: [ book.id, 1 ]) do
      post rerun_generation_admin_book_url(book)
    end

    book.reload
    assert_predicate book, :pending?
    assert_equal 1, book.generation_attempt
    assert_equal({}, book.generation_failure)
    assert_equal "req_original", book.generation_failure_history.last.fetch("request_id")
  end

  test "forbids non-administrators from rerunning a book" do
    sign_in users(:one)

    post rerun_generation_admin_book_url(books(:one))

    assert_response :forbidden
  end
end
