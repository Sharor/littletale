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
    admin.update!(admin: true)
    sign_in admin

    assert_enqueued_with(job: GenerateBookJob, args: [ book.id, 1 ]) do
      post rerun_generation_admin_book_url(book)
    end

    book.reload
    assert_predicate book, :pending?
    assert_equal 1, book.generation_attempt
    assert_equal({}, book.generation_failure)
    assert_equal "req_original", book.generation_failure_history.last.fetch("request_id")
    assert_predicate book.trial_book_reservations.held, :exists?
  end

  test "rerunning a released failed book reserves another available slot" do
    owner = users(:one)
    owner.update!(tier: "free")
    book = owner.books.create!(name: "Released failure", total_pages: 1, generation_status: :failed)
    released = TrialBookReservation.reserve_for!(book)
    released.release!(reason: "admin_released_failed_book")
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    assert_difference("book.trial_book_reservations.held.count", 1) do
      post rerun_generation_admin_book_url(book)
    end

    assert_predicate book.reload, :pending?
  end

  test "forbids non-administrators from rerunning a book" do
    sign_in users(:one)

    post rerun_generation_admin_book_url(books(:one))

    assert_response :forbidden
  end

  test "does not rerun a book that is not failed" do
    book = Book.create!(user: users(:one), name: "Still generating", total_pages: 1, generation_status: :in_progress)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    assert_no_enqueued_jobs only: GenerateBookJob do
      post rerun_generation_admin_book_url(book)
    end

    assert_redirected_to admin_failed_books_url
    assert_equal 0, book.reload.generation_attempt
  end
end
