# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class UserTrialTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(tier: "free", admin: false)
  end

  test "a free user starts with three available trial books" do
    assert_equal "not_started", @user.trial_status
    assert_equal 3, @user.trial_books_remaining
    assert_not_predicate @user, :trial_expired?
  end

  test "held reservations consume the trial allowance and a fourth book is rejected" do
    3.times do |number|
      book = @user.books.create!(name: "Trial book #{number}", total_pages: 1)
      TrialBookReservation.reserve_for!(book)
    end

    fourth = @user.books.create!(name: "One too many", total_pages: 1)

    assert_raises(TrialBookReservation::LimitReached) do
      TrialBookReservation.reserve_for!(fourth)
    end
    assert_equal 0, @user.trial_books_remaining
  end

  test "an administrator can release a failed book slot and the release remains auditable" do
    book = @user.books.create!(name: "Failed trial book", total_pages: 1, generation_status: :failed)
    reservation = TrialBookReservation.reserve_for!(book)
    admin = users(:three)
    admin.update!(admin: true)

    assert reservation.release!(by: admin, reason: "admin_released_failed_book")
    assert_not reservation.release!(by: admin, reason: "admin_released_failed_book")

    reservation.reload
    assert_equal "released", reservation.status
    assert_equal admin, reservation.released_by
    assert_not_nil reservation.released_at
    assert_equal "admin_released_failed_book", reservation.release_reason
    assert_equal 3, @user.trial_books_remaining
  end

  test "the first completed reserved book starts one calendar month of access only once" do
    first_book = @user.books.create!(name: "First complete book", total_pages: 1)
    second_book = @user.books.create!(name: "Second complete book", total_pages: 1)
    TrialBookReservation.reserve_for!(first_book)
    TrialBookReservation.reserve_for!(second_book)

    travel_to Time.zone.local(2026, 1, 31, 12) do
      first_book.update!(generation_status: :completed)

      assert_equal Time.current, @user.reload.trial_started_at
      assert_equal Time.zone.local(2026, 2, 28, 12), @user.trial_expires_at
    end

    travel_to Time.zone.local(2026, 2, 1, 12) do
      second_book.update!(generation_status: :completed)
      assert_equal Time.zone.local(2026, 1, 31, 12), @user.reload.trial_started_at
      assert_equal Time.zone.local(2026, 2, 28, 12), @user.trial_expires_at
    end
  end

  test "trial status changes from active to expired at the deadline" do
    @user.update!(trial_started_at: 1.month.ago, trial_expires_at: 1.second.from_now)
    assert_equal "active", @user.trial_status

    travel 2.seconds do
      assert_equal "expired", @user.trial_status
      assert_predicate @user, :trial_expired?
    end
  end

  test "non-free users are paid and have no trial book limit" do
    @user.update!(tier: "basic")

    assert_equal "paid", @user.access_type
    assert_equal "paid", @user.trial_status
    assert_nil @user.trial_books_remaining
  end

  test "an illustration retry reserves its token before handing work to the queue adapter" do
    book = @user.books.create!(name: "Commit before enqueue", total_pages: 1, generation_status: :failed)
    page = book.pages.create!(text: "A page", generation_attempt: book.generation_attempt)
    illustration = page.create_illustration!(original_description: "A scene")
    queued_token = nil

    enqueue_reserved = lambda do |image, token|
      queued_token = token
      assert_equal token, PageIllustrationGeneration.state(image.reload)["token"]
      assert_equal "queued", PageIllustrationGeneration.state(image)["status"]
      true
    end

    PageIllustrationGeneration.stub :enqueue_reserved!, enqueue_reserved do
      assert book.enqueue_illustration_retry!(illustration, actor: @user)
    end

    assert_not_nil queued_token
    assert_predicate book.trial_book_reservations.held, :exists?
  end

  test "one page's failed queue handoff does not release the slot backing another page retry" do
    book = @user.books.create!(name: "Two retries", total_pages: 2, generation_status: :failed)
    first_page = book.pages.create!(text: "First", generation_attempt: book.generation_attempt)
    second_page = book.pages.create!(text: "Second", generation_attempt: book.generation_attempt)
    first = first_page.create_illustration!(original_description: "First scene")
    second = second_page.create_illustration!(original_description: "Second scene")

    enqueue_reserved = lambda do |image, token|
      if image == first
        PageIllustrationGeneration.release_queue_reservation!(image, token)
        assert book.enqueue_illustration_retry!(second, actor: @user)
        false
      else
        true
      end
    end

    PageIllustrationGeneration.stub :enqueue_reserved!, enqueue_reserved do
      assert_not book.enqueue_illustration_retry!(first, actor: @user)
    end

    assert_equal "queued", PageIllustrationGeneration.state(second.reload)["status"]
    assert_predicate book.trial_book_reservations.held, :exists?
  end

  test "only one stale failed-book rerun can advance the generation attempt" do
    book = @user.books.create!(name: "Concurrent rerun", total_pages: 1, generation_status: :failed)
    first_request = Book.find(book.id)
    stale_request = Book.find(book.id)

    assert_equal 1, first_request.prepare_failed_regeneration!
    assert_nil stale_request.prepare_failed_regeneration!
    assert_equal 1, book.reload.generation_attempt
    assert_equal 1, book.trial_book_reservations.held.count
  end

  test "a released book reacquires a slot before it can complete" do
    book = @user.books.create!(name: "Finishing retry", total_pages: 1, generation_status: :failed)
    reservation = TrialBookReservation.reserve_for!(book)
    reservation.release!(reason: "admin_released_failed_book")
    page = book.pages.create!(text: "The end", generation_attempt: book.generation_attempt)
    page.create_illustration!(original_description: "The end",
      original_image: File.open(file_fixture("character.png")))

    book.refresh_generation_status!

    assert_predicate book.reload, :completed?
    assert_predicate book.trial_book_reservations.held, :exists?
    assert_not_nil @user.reload.trial_started_at
  end

  test "a released book cannot complete after all trial slots are used elsewhere" do
    book = @user.books.create!(name: "Blocked completion", total_pages: 1, generation_status: :failed)
    reservation = TrialBookReservation.reserve_for!(book)
    reservation.release!(reason: "admin_released_failed_book")
    3.times do |number|
      held_book = @user.books.create!(name: "Replacement #{number}", total_pages: 1)
      TrialBookReservation.reserve_for!(held_book)
    end
    page = book.pages.create!(text: "The end", generation_attempt: book.generation_attempt)
    page.create_illustration!(original_description: "The end",
      original_image: File.open(file_fixture("character.png")))

    assert_raises(TrialBookReservation::LimitReached) do
      book.refresh_generation_status!
    end

    assert_predicate book.reload, :failed?
    assert_not_predicate book.trial_book_reservations.held, :exists?
  end
end
