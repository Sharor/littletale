# frozen_string_literal: true

require "test_helper"

class Admin::FailedBooksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "asks guests to sign in" do
    get admin_failed_books_url
    assert_redirected_to new_user_session_path
  end

  test "forbids signed-in non-administrators" do
    sign_in users(:one)
    get admin_failed_books_url
    assert_response :forbidden
  end

  test "lists failed books and their persisted investigation metadata for administrators" do
    book = Book.create!(user: users(:one), name: "Blocked book", total_pages: 1)
    book.update!(
      generation_status: :failed,
      generation_failed_at: Time.current,
      generation_failure: { "message" => "Rejected by the safety system", "request_id" => "req_blocked", "account_access" => "trial" }
    )
    TrialBookReservation.reserve_for!(book)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    get admin_failed_books_url

    assert_response :success
    assert_select "h1", "Failed book generations"
    assert_select "h2", "Blocked book"
    assert_select "[data-account-access='trial']", text: /Trial/
    assert_select "[data-quota-status='held']", text: /slot reserved/i
    assert_select "form[action='#{release_trial_slot_admin_book_path(book)}']"
    assert_select "pre", /req_blocked/
  end

  test "an administrator releases a failed book trial slot" do
    owner = users(:one)
    owner.update!(tier: "free")
    book = owner.books.create!(name: "Failed trial book", total_pages: 1, generation_status: :failed)
    reservation = TrialBookReservation.reserve_for!(book)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    assert_difference("owner.trial_books_remaining", 1) do
      post release_trial_slot_admin_book_url(book)
    end

    assert_redirected_to admin_failed_books_url
    assert_equal "released", reservation.reload.status
    assert_equal admin, reservation.released_by
    assert_equal "admin_released_failed_book", reservation.release_reason
  end

  test "an administrator cannot release a slot while an illustration retry is queued" do
    owner = users(:one)
    owner.update!(tier: "free")
    book = owner.books.create!(name: "Retrying trial book", total_pages: 1, generation_status: :failed)
    page = book.pages.create!(text: "A page", generation_attempt: book.generation_attempt)
    illustration = page.create_illustration!(original_description: "A scene")
    reservation = TrialBookReservation.reserve_for!(book)
    PageIllustrationGeneration.reserve!(illustration, retrying: true)
    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin

    get admin_failed_books_url
    assert_select "[data-quota-status='retrying']", text: /cannot be released/i
    assert_select "form[action='#{release_trial_slot_admin_book_path(book)}']", count: 0

    assert_no_changes("reservation.reload.status") do
      post release_trial_slot_admin_book_url(book)
    end

    assert_redirected_to admin_failed_books_url
    assert_equal "held", reservation.status
  end
end
