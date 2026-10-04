# frozen_string_literal: true

require "test_helper"

class ParentalGenerationGateTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @book = @user.books.create!(name: "A guarded story", total_pages: 1)
    @character = @user.characters.create!(name: "Guarded hero")
  end

  test "allows generation when parental restrictions are disabled" do
    decision = ParentalGenerationGate.authorize(@book)

    assert decision.allowed?
    assert_nil decision.request
  end

  test "approval mode creates one pending request for a book" do
    enable_control(mode: "approval_required")

    first = ParentalGenerationGate.authorize(@book)
    second = ParentalGenerationGate.authorize(@book)

    assert first.pending?
    assert_equal first.request, second.request
    assert_equal "book", first.request.kind
    assert_equal "pending", first.request.status
  end

  test "approval mode creates a pending request for a character" do
    enable_control(mode: "approval_required")

    decision = ParentalGenerationGate.authorize(@character)

    assert decision.pending?
    assert_equal @character, decision.request.generatable
    assert_equal "character", decision.request.kind
  end

  test "daily mode leaves character generation to existing credits" do
    enable_control(mode: "daily_limit")
    activate_subscription

    decision = ParentalGenerationGate.authorize(@character)

    assert decision.allowed?
    assert_nil decision.request
  end

  test "daily mode reserves a book slot and blocks another active book" do
    enable_control(mode: "daily_limit", daily_book_limit: 1)
    activate_subscription

    first = ParentalGenerationGate.authorize(@book)
    another = @user.books.create!(name: "Second guarded story", total_pages: 1)
    second = ParentalGenerationGate.authorize(another)

    assert first.allowed?
    assert_equal "approved", first.request.status
    assert second.limit_reached?
    assert_nil second.request
  end

  test "an administrator bypasses a full parental daily allowance" do
    @user.update!(admin: true)
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    completed = @user.books.create!(name: "Already completed", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "daily_limit", request_key: "completed-admin-book", status: "completed",
      completed_at: Time.current)

    assert_no_difference("control.generation_requests.count") do
      decision = ParentalGenerationGate.authorize(@book)

      assert decision.allowed?
      assert_nil decision.request
    end
  end

  test "an administrator releases existing parental requests before generation" do
    enable_control(mode: "approval_required")
    book_request = ParentalGenerationGate.authorize(@book).request
    character_request = ParentalGenerationGate.authorize(@character).request
    character_request.approve!
    @user.update!(admin: true)

    book_decision = ParentalGenerationGate.authorize(@book)
    character_decision = ParentalGenerationGate.authorize(@character)

    assert book_decision.allowed?
    assert character_decision.allowed?
    assert_equal "released", book_request.reload.status
    assert_equal "released", character_request.reload.status
  end

  test "daily mode counts successful books completed in the local day" do
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    activate_subscription
    completed = @user.books.create!(name: "Already completed", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "daily_limit", request_key: "completed-book", status: "completed",
      completed_at: Time.current)

    decision = ParentalGenerationGate.authorize(@book)

    assert decision.limit_reached?
  end

  test "released daily reservations do not consume the allowance" do
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    activate_subscription
    failed = @user.books.create!(name: "Failed story", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: failed, kind: "book",
      policy_mode: "daily_limit", request_key: "failed-book", status: "released")

    assert ParentalGenerationGate.authorize(@book).allowed?
  end

  test "a retry in approval mode reuses an approved request without asking again" do
    enable_control(mode: "approval_required")
    request = ParentalGenerationGate.authorize(@book).request
    request.approve!

    decision = ParentalGenerationGate.authorize(@book, retrying: true)

    assert decision.allowed?
    assert_equal request, decision.request
  end

  test "a technical retry does not require approval when the original predates parent controls" do
    enable_control(mode: "approval_required")

    decision = ParentalGenerationGate.authorize(@book, retrying: true)

    assert decision.allowed?
    assert_nil decision.request
  end

  test "daily mode counts books approved under the prior mode when they finish today" do
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    activate_subscription
    completed = @user.books.create!(name: "Approved earlier", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "approval_required", request_key: "approved-earlier", status: "completed",
      completed_at: Time.current)

    assert ParentalGenerationGate.authorize(@book).limit_reached?
  end

  test "daily mode applies its capacity to a failed book approved under the prior mode" do
    control = enable_control(mode: "approval_required", daily_book_limit: 1)
    prior_approval = ParentalGenerationGate.authorize(@book).request
    prior_approval.approve!
    @book.update_columns(generation_status: Book.generation_statuses.fetch("failed"))
    control.update!(mode: "daily_limit")
    activate_subscription
    completed = @user.books.create!(name: "Completed before retry", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "daily_limit", request_key: "completed-before-retry", status: "completed",
      completed_at: Time.current)

    decision = ParentalGenerationGate.authorize(@book, retrying: true)

    assert decision.limit_reached?
    assert_equal "approved", prior_approval.reload.status
  end

  test "daily mode converts a prior approval to a reservation when capacity is available" do
    control = enable_control(mode: "approval_required", daily_book_limit: 1)
    prior_approval = ParentalGenerationGate.authorize(@book).request
    prior_approval.approve!
    @book.update_columns(generation_status: Book.generation_statuses.fetch("failed"))
    control.update!(mode: "daily_limit")
    activate_subscription

    decision = ParentalGenerationGate.authorize(@book, retrying: true)

    assert decision.allowed?
    assert_equal prior_approval, decision.request
    assert_equal "daily_limit", prior_approval.reload.policy_mode
    assert_equal control.local_date, prior_approval.reserved_on
  end

  test "an older failed approval does not occupy a daily slot" do
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    activate_subscription
    failed = @user.books.create!(name: "Failed approved story", total_pages: 1, generation_status: :failed)
    control.generation_requests.create!(user: @user, generatable: failed, kind: "book",
      policy_mode: "approval_required", request_key: "failed-approved", status: "approved")

    assert ParentalGenerationGate.authorize(@book).allowed?
  end

  test "a pending fallback request cannot bypass the daily limit after subscription renewal" do
    control = enable_control(mode: "daily_limit", daily_book_limit: 1)
    pending = ParentalGenerationGate.authorize(@book).request
    assert_equal "pending", pending.status

    activate_subscription
    completed = @user.books.create!(name: "Completed after renewal", total_pages: 1)
    control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "daily_limit", request_key: "complete-after-renewal", status: "completed",
      completed_at: Time.current)

    decision = ParentalGenerationGate.authorize(@book)

    assert decision.limit_reached?
    assert_equal "pending", pending.reload.status
  end

  test "a pending fallback request becomes a daily reservation when capacity is available" do
    enable_control(mode: "daily_limit", daily_book_limit: 1)
    pending = ParentalGenerationGate.authorize(@book).request
    activate_subscription

    decision = ParentalGenerationGate.authorize(@book)

    assert decision.allowed?
    assert_equal pending, decision.request
    assert_equal "approved", pending.reload.status
    assert_equal "daily_limit", pending.policy_mode
  end

  test "daily mode releases an obsolete pending character approval" do
    control = enable_control(mode: "daily_limit")
    pending = ParentalGenerationGate.authorize(@character).request
    activate_subscription

    decision = ParentalGenerationGate.authorize(@character)

    assert decision.allowed?
    assert_nil decision.request
    assert_equal "released", pending.reload.status
    assert_empty control.generation_requests.pending
  end

  private

  def enable_control(mode:, daily_book_limit: 2)
    @user.create_parent_control!(enabled: true, mode: mode, daily_book_limit: daily_book_limit,
      pin: "4826", pin_confirmation: "4826")
  end

  def activate_subscription
    @user.user_subscriptions.create!(status: "active", product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid)
  end
end
