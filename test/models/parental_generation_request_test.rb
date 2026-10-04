# frozen_string_literal: true

require "test_helper"

class ParentalGenerationRequestTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    @book = @user.books.create!(name: "Tracked story", total_pages: 1)
  end

  test "book completion records one successful generation" do
    request = create_request(status: "approved")

    @book.update!(generation_status: :completed)

    assert_equal "completed", request.reload.status
    assert_not_nil request.completed_at
  end

  test "a failed daily book releases its active capacity" do
    request = create_request(status: "approved", policy_mode: "daily_limit")

    @book.update!(generation_status: :failed)

    assert_equal "released", request.reload.status
  end

  test "a failed book keeps its explicit parent approval for retries" do
    request = create_request(status: "approved", policy_mode: "approval_required")

    @book.update!(generation_status: :failed)

    assert_equal "approved", request.reload.status
  end

  test "request ownership must match the parent control and generated record" do
    other_user = users(:two)
    other_book = other_user.books.create!(name: "Someone else's story", total_pages: 1)

    wrong_user = @control.generation_requests.new(user: other_user, generatable: @book, kind: "book",
      policy_mode: "approval_required", request_key: SecureRandom.hex, status: "pending")
    wrong_book = @control.generation_requests.new(user: @user, generatable: other_book, kind: "book",
      policy_mode: "approval_required", request_key: SecureRandom.hex, status: "pending")

    assert_not wrong_user.valid?
    assert_not wrong_book.valid?
  end

  private

  def create_request(status:, policy_mode: "approval_required")
    @control.generation_requests.create!(user: @user, generatable: @book, kind: "book",
      policy_mode: policy_mode, request_key: SecureRandom.hex, status: status)
  end
end
