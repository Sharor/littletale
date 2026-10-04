# frozen_string_literal: true

require "test_helper"

class Parent::DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @control = @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    sign_in @user
  end

  test "dashboard redirects to the pin screen until unlocked" do
    get parent_url

    assert_redirected_to new_parent_session_url
  end

  test "correct pin unlocks the dashboard" do
    post parent_session_url, params: { pin: "4826" }

    assert_redirected_to parent_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Parent dashboard/
  end

  test "incorrect pin does not unlock the dashboard" do
    post parent_session_url, params: { pin: "1111" }

    assert_response :unprocessable_content
    get parent_url
    assert_redirected_to new_parent_session_url
  end

  test "dashboard reports successful books and pending approvals" do
    unlock_parent
    book = @user.books.create!(name: "Finished today", total_pages: 1)
    @control.generation_requests.create!(user: @user, generatable: book, kind: "book",
      policy_mode: "approval_required", request_key: "finished", status: "completed", completed_at: Time.current)
    character = @user.characters.create!(name: "Waiting hero")
    pending = @control.generation_requests.create!(user: @user, generatable: character, kind: "character",
      policy_mode: "approval_required", request_key: "waiting", status: "pending")

    get parent_url

    assert_response :success
    assert_select "[data-successful-books-today='1']"
    assert_select "[data-parental-request-id='#{pending.id}']", text: /Waiting hero/
  end

  test "dashboard shows recent parent decisions" do
    unlock_parent
    book = @user.books.create!(name: "Declined story", plot: "A dragon learns to share.", total_pages: 1)
    decided = @control.generation_requests.create!(user: @user, generatable: book, kind: "book",
      policy_mode: "approval_required", request_key: "declined", status: "declined", decided_at: Time.current)

    get parent_url

    assert_select "[data-recent-parental-request-id='#{decided.id}']", text: /Declined story.*Declined/m do
      assert_select "[data-parent-book-details]", text: /Title:\s*Declined story.*Plot:\s*A dragon learns to share\./m
      assert_select "button.parent-request-action--declined[disabled]", text: "Declined"
      assert_select "button[type='button'][data-action='confirmation-dialog#open']", text: "Approve"
      assert_select "dialog[data-confirmation-dialog-target='dialog']" do
        assert_select "p", text: "Are you sure? You already declined this book, and this will make the book immediately instead."
        assert_select "form[action='#{approve_parent_generation_request_path(decided)}'] button", text: "Approve"
      end
    end
  end

  test "dashboard shows the title and plot for a book awaiting approval" do
    unlock_parent
    book = @user.books.create!(name: "The moonlit map", plot: "Two friends follow a silver trail.", total_pages: 1)
    pending = @control.generation_requests.create!(user: @user, generatable: book, kind: "book",
      policy_mode: "approval_required", request_key: "book-details", status: "pending")

    get parent_url

    assert_select "[data-parental-request-id='#{pending.id}'] [data-parent-book-details]",
      text: /Title:\s*The moonlit map.*Plot:\s*Two friends follow a silver trail\./m
  end

  test "dashboard removes requests whose generated record was deleted" do
    unlock_parent
    book = @user.books.create!(name: "Deleted story", total_pages: 1)
    orphan = @control.generation_requests.create!(user: @user, generatable: book, kind: "book",
      policy_mode: "approval_required", request_key: "deleted", status: "declined", decided_at: Time.current)
    Book.where(id: book.id).delete_all

    get parent_url

    assert_response :success
    assert_not ParentalGenerationRequest.exists?(orphan.id)
  end

  test "daily dashboard shows remaining capacity and excludes failed books from in-progress" do
    unlock_parent
    @user.user_subscriptions.create!(status: "active", product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid)
    @control.update!(mode: "daily_limit", daily_book_limit: 3)
    completed = @user.books.create!(name: "Completed today", total_pages: 1, generation_status: :completed)
    @control.generation_requests.create!(user: @user, generatable: completed, kind: "book",
      policy_mode: "daily_limit", request_key: "completed", status: "completed", completed_at: Time.current)
    failed = @user.books.create!(name: "Failed earlier", total_pages: 1, generation_status: :failed)
    @control.generation_requests.create!(user: @user, generatable: failed, kind: "book",
      policy_mode: "approval_required", request_key: "failed", status: "approved")

    get parent_url

    assert_select "[data-in-progress-books='0']"
    assert_select "[data-remaining-book-slots='2']"
  end

  test "parent session can be locked again" do
    unlock_parent

    delete parent_session_url

    assert_redirected_to profile_url
    get parent_url
    assert_redirected_to new_parent_session_url
  end

  test "parent access expires after thirty minutes" do
    unlock_parent

    travel 31.minutes do
      get parent_url
      assert_redirected_to new_parent_session_url
    end
  end

  test "changing the pin invalidates an older unlocked session" do
    unlock_parent
    @control.update!(pin: "7391", pin_confirmation: "7391")

    get parent_url

    assert_redirected_to new_parent_session_url
  end

  private

  def unlock_parent
    post parent_session_url, params: { pin: "4826" }
  end
end
