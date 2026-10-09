# frozen_string_literal: true

require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:three)
    @admin.update!(admin: true)
  end

  test "user access is admin only" do
    get admin_users_url
    assert_response :forbidden

    sign_in users(:one)
    get admin_users_url
    assert_response :forbidden
  end

  test "admin can search users by partial email and open a user" do
    sign_in @admin

    get admin_users_url, params: { query: "HI@THERE" }

    assert_response :success
    assert_select "h1", "User access"
    assert_select "input[name='query'][value='HI@THERE']"
    assert_select "tr[data-user-id='#{users(:one).id}'] a[href='#{admin_user_path(users(:one))}']",
      text: users(:one).email
    assert_select "tr[data-user-id='#{users(:two).id}']", count: 0
    assert_select "tr[data-user-id='#{@admin.id}']", count: 0
  end

  test "admin can search for inspect and restore books for another administrator" do
    inspected_admin = users(:two)
    inspected_admin.update!(admin: true)
    deleted = inspected_admin.books.create!(name: "Administrator story", total_pages: 1)
    deleted.soft_delete!
    sign_in @admin

    get admin_users_url, params: { query: "HELLO@WORLD" }

    assert_response :success
    assert_select "tr[data-user-id='#{inspected_admin.id}'] a[href='#{admin_user_path(inspected_admin)}']",
      text: inspected_admin.email

    get admin_user_url(inspected_admin)

    assert_response :success
    assert_select "section[data-deleted-books]", text: /Administrator story/
    assert_select "form[action='#{restore_admin_user_book_path(inspected_admin, deleted)}']"

    post restore_admin_user_book_url(inspected_admin, deleted)

    assert_redirected_to admin_user_url(inspected_admin)
    assert_nil deleted.reload.deleted_at
  end

  test "user page separates current and deleted books" do
    owner = users(:one)
    current = owner.books.create!(name: "Current story", total_pages: 1)
    deleted = owner.books.create!(name: "Deleted story", total_pages: 1)
    deleted.soft_delete!
    sign_in @admin

    get admin_user_url(owner)

    assert_response :success
    assert_select "section[data-current-books]", text: /Current story/
    assert_select "section[data-current-books]", text: /Deleted story/, count: 0
    assert_select "section[data-deleted-books]", text: /Deleted story/
    assert_select "section[data-deleted-books]", text: /Current story/, count: 0
    assert_select "form[action='#{restore_admin_user_book_path(owner, deleted)}']"
  end

  test "restoring a pending review book keeps it pending" do
    owner = users(:one)
    owner.tutorial.update!(terms: true)
    owner.create_parent_control!(enabled: true, mode: "approval_required", pin: "4826", pin_confirmation: "4826")
    book = owner.books.create!(name: "Restore pending story", total_pages: 1)
    request = ParentalGenerationGate.authorize(book).request
    book.soft_delete!
    sign_in @admin

    post restore_admin_user_book_url(owner, book)

    assert_redirected_to admin_user_url(owner)
    assert_nil book.reload.deleted_at
    assert_predicate request.reload, :pending?

    sign_out @admin
    sign_in owner
    get awaiting_approval_books_url
    assert_select ".library-book", text: /Restore pending story/
  end

  test "admin can restore a legacy book that does not pass current creation validations" do
    owner = users(:one)
    legacy_book = books(:one)
    legacy_book.update_column(:deleted_at, Time.current)
    sign_in @admin

    post restore_admin_user_book_url(owner, legacy_book)

    assert_redirected_to admin_user_url(owner)
    assert_nil legacy_book.reload.deleted_at
  end

  test "restore rejects an active book and a book owned by another user" do
    owner = users(:one)
    active = owner.books.create!(name: "Active story", total_pages: 1)
    deleted_elsewhere = users(:two).books.create!(name: "Other deleted story", total_pages: 1)
    deleted_elsewhere.soft_delete!
    sign_in @admin

    post restore_admin_user_book_url(owner, active)
    assert_response :not_found

    sign_in @admin
    post restore_admin_user_book_url(owner, deleted_elsewhere)
    assert_response :not_found
  end

  test "admin can see and clear a user's parent PIN lockout" do
    owner = users(:one)
    control = owner.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826",
      failed_pin_attempts: ParentControl::MAX_PIN_ATTEMPTS, locked_until: 10.minutes.from_now)
    sign_in @admin

    get admin_user_url(owner)

    assert_response :success
    assert_select "[data-parent-pin-status='locked']", text: /locked/i
    assert_select "form[action='#{unlock_parent_pin_admin_user_path(owner)}'] button", text: "Clear PIN lockout"

    post unlock_parent_pin_admin_user_url(owner)

    assert_redirected_to admin_user_url(owner)
    control.reload
    assert_equal 0, control.failed_pin_attempts
    assert_nil control.locked_until
  end

  test "ordinary users cannot clear a parent PIN lockout" do
    owner = users(:one)
    control = owner.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826",
      failed_pin_attempts: ParentControl::MAX_PIN_ATTEMPTS, locked_until: 10.minutes.from_now)
    sign_in users(:two)

    post unlock_parent_pin_admin_user_url(owner)

    assert_response :forbidden
    assert_predicate control.reload, :pin_locked?
  end
end
