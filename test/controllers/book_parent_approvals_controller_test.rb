# frozen_string_literal: true

require "test_helper"

class BookParentApprovalsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @control = @user.create_parent_control!(enabled: true, mode: "approval_required",
      pin: "4826", pin_confirmation: "4826")
    @book = @user.books.create!(name: "Waiting for a parent", plot: "A fox searches for a hidden garden.", total_pages: 1)
    @generation_request = ParentalGenerationGate.authorize(@book).request
    sign_in @user
  end

  test "approval page explains the wait and offers parent pin approval" do
    get "/books/#{@book.id}/parent_approval"

    assert_response :success
    assert_select "h1", text: /A parent needs to approve this book/i
    assert_select "[data-parent-book-details]",
      text: /Title:\s*Waiting for a parent.*Plot:\s*A fox searches for a hidden garden\./m
    assert_select "input[name='pin'][type='password']"
    assert_select "form[action='/books/#{@book.id}/parent_approval'] button", text: /Approve as parent/
  end

  test "correct pin approves and starts the book" do
    assert_enqueued_with(job: GenerateBookJob) do
      post "/books/#{@book.id}/parent_approval", params: { pin: "4826" }
    end

    assert_redirected_to book_url(@book)
    assert_equal "approved", @generation_request.reload.status
    assert_predicate @book.trial_book_reservations.held, :exists?
  end

  test "incorrect pin leaves the book awaiting approval" do
    assert_no_enqueued_jobs only: GenerateBookJob do
      post "/books/#{@book.id}/parent_approval", params: { pin: "1111" }
    end

    assert_response :unprocessable_content
    assert_equal "pending", @generation_request.reload.status
    assert_select "[role='alert']", text: /PIN is incorrect/
  end

  test "another account cannot approve the book" do
    sign_out @user
    other_user = users(:two)
    other_user.create_tutorial!(terms: true) unless other_user.tutorial
    other_user.tutorial.update!(terms: true)
    sign_in other_user

    post "/books/#{@book.id}/parent_approval", params: { pin: "4826" }

    assert_response :not_found
    assert_equal "pending", @generation_request.reload.status
  end

  test "parent pins are filtered from request logs" do
    filtered = ActiveSupport::ParameterFilter.new(
      Rails.application.config.filter_parameters
    ).filter({ pin: "4826", current_parent_pin: "7391", parent_pin: "8842" })

    assert_equal({ pin: "[FILTERED]", current_parent_pin: "[FILTERED]", parent_pin: "[FILTERED]" }, filtered)
  end
end
