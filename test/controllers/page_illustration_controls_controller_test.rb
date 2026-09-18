# frozen_string_literal: true

require "test_helper"

class PageIllustrationControlsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free")
    @user.tutorial.update!(terms: true)
    @book = @user.books.create!(name: "Incomplete trial book", total_pages: 1, generation_status: :failed)
    @page = @book.pages.create!(text: "An unfinished page", generation_attempt: @book.generation_attempt)
    @illustration = @page.create_illustration!(original_description: "A moonlit path")
    sign_in @user
  end

  test "the owner sees an illustration retry within the existing attempt limit" do
    get illustration_controls_page_url(@page)

    assert_response :success
    assert_select "form[action='#{regenerate_illustration_page_path(@page)}']", count: 1
    assert_select "p", text: /1 of 3 attempts used/
  end

  test "the owner queues an illustration retry" do
    assert_enqueued_jobs 1, only: RegeneratePageIllustrationJob do
      post regenerate_illustration_page_url(@page), headers: { "HTTP_REFERER" => book_url(@book) }
    end

    assert_redirected_to book_url(@book)
    assert_equal 2, PageIllustrationGeneration.attempts(@illustration.reload).length
    assert_nil PageIllustrationGeneration.attempts(@illustration).last["admin_id"]
    assert_predicate @book.trial_book_reservations.held, :exists?
  end

  test "retrying a released failed book reacquires an available trial slot" do
    released = TrialBookReservation.reserve_for!(@book)
    released.release!(reason: "admin_released_failed_book")

    assert_enqueued_jobs 1, only: RegeneratePageIllustrationJob do
      post regenerate_illustration_page_url(@page)
    end

    assert_predicate @book.trial_book_reservations.held, :exists?
  end

  test "a released failed book cannot retry an illustration when all slots are held" do
    released = TrialBookReservation.reserve_for!(@book)
    released.release!(reason: "admin_released_failed_book")
    3.times do |number|
      held_book = @user.books.create!(name: "Held #{number}", total_pages: 1)
      TrialBookReservation.reserve_for!(held_book)
    end

    assert_no_enqueued_jobs only: RegeneratePageIllustrationJob do
      post regenerate_illustration_page_url(@page)
    end

    assert_equal 1, PageIllustrationGeneration.attempts(@illustration.reload).length
    assert_not_predicate @book.trial_book_reservations.held, :exists?
  end

  test "another user cannot retry the owner's illustration" do
    sign_in users(:two)

    assert_no_enqueued_jobs only: RegeneratePageIllustrationJob do
      post regenerate_illustration_page_url(@page)
    end

    assert_response :not_found
  end

  test "the owner cannot retry after three illustration attempts" do
    attempts = 3.times.map { |index| { "number" => index + 1, "status" => "failed" } }
    @illustration.update!(generation_metadata: { "page_generation" => { "status" => "failed", "attempts" => attempts } })

    get illustration_controls_page_url(@page)

    assert_response :success
    assert_select "form[action='#{regenerate_illustration_page_path(@page)}']", count: 0
    assert_select "p", text: /3 of 3 attempts used/
  end
end
