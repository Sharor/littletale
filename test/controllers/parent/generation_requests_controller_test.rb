# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Parent::GenerationRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    sign_in @user
    post parent_session_url, params: { pin: "4826" }
  end

  test "approving a book reserves funding and queues generation" do
    book = @user.books.create!(name: "Waiting story", total_pages: 1)
    request = pending_request(book, "book")

    assert_enqueued_with(job: GenerateBookJob) do
      post approve_parent_generation_request_url(request)
    end

    assert_redirected_to parent_url
    assert_equal "approved", request.reload.status
    assert_predicate book.trial_book_reservations.held, :exists?
  end

  test "approving a character queues its image generation" do
    character = @user.characters.create!(name: "Waiting hero", age: 9, gender: "Girl", ethnicity: "Asian",
      hair_color: "Black", hair_style: "Long", eye_color: "Brown")
    request = pending_request(character, "character")

    assert_enqueued_jobs 1 do
      post approve_parent_generation_request_url(request)
    end

    assert_redirected_to parent_url
    assert_equal "approved", request.reload.status
    assert_not_nil character.reload.current_image_request
  end

  test "declining a request never queues generation" do
    book = @user.books.create!(name: "Declined story", total_pages: 1)
    request = pending_request(book, "book")

    assert_no_enqueued_jobs only: GenerateBookJob do
      post decline_parent_generation_request_url(request)
    end

    assert_equal "declined", request.reload.status
    assert_not_nil book.reload.deleted_at

    get books_url
    assert_select ".library-book", text: /Declined story/, count: 0
  end

  test "approving a declined book restores and generates it" do
    book = @user.books.create!(name: "Restored story", total_pages: 1)
    request = pending_request(book, "book")
    request.decline!
    book.update!(deleted_at: Time.current)

    assert_enqueued_with(job: GenerateBookJob) do
      post approve_parent_generation_request_url(request)
    end

    assert_redirected_to parent_url
    assert_equal "approved", request.reload.status
    assert_nil book.reload.deleted_at
  end

  test "an approved book reports a queue failure instead of claiming it was queued" do
    book = @user.books.create!(name: "Unqueued approved story", total_pages: 1)
    request = pending_request(book, "book")
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    GenerateBookJob.stub(:perform_later, failed_job) do
      post approve_parent_generation_request_url(request)
    end

    assert_redirected_to parent_url
    assert_match(/could not be queued/i, flash[:alert])
    assert_equal "approved", request.reload.status
    assert_predicate book.reload, :failed?
  end

  test "a parent cannot decide another account's request" do
    other = users(:two)
    other_control = other.create_parent_control!(enabled: true, pin: "7391", pin_confirmation: "7391")
    book = other.books.create!(name: "Private request", total_pages: 1)
    request = other_control.generation_requests.create!(user: other, generatable: book, kind: "book",
      policy_mode: "approval_required", request_key: "private", status: "pending")

    post approve_parent_generation_request_url(request)

    assert_response :not_found
    assert_equal "pending", request.reload.status
  end

  private

  def pending_request(generatable, kind)
    request = ParentalGenerationGate.authorize(generatable).request
    assert_equal kind, request.kind
    request
  end
end
