# frozen_string_literal: true

require "test_helper"

class BooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.update!(tier: "free")
    @user.tutorial.update!(terms: true)
    @book = books(:one)
    sign_in @user
  end

  test "index renders only the signed-in user's books" do
    private_book = Book.create!(user: users(:two), name: "Private", total_pages: 1)

    get books_url

    assert_response :success
    assert_select "h2", "Current Library"
    assert_select "h3", text: @book.name
    assert_select "h3", text: private_book.name, count: 0
  end

  test "new renders the page limit for the user's tier" do
    get new_book_url

    assert_response :success
    assert_select "form[action='#{books_path}']"
    assert_select "input[name='book[total_pages]'][max='5']"
    assert_select "strong", "5 pages"
  end

  test "create clamps pages to the tier limit and queues generation" do
    assert_difference("Book.count", 1) do
      assert_enqueued_with(job: GenerateBookJob) do
        post books_url, params: { book: { name: "A new tale", plot: "Adventure", total_pages: 12 } }
      end
    end

    book = Book.find_by!(name: "A new tale", user: @user)
    assert_equal 5, book.total_pages
    assert_redirected_to book_url(book, format: :html)
  end

  test "does not expose another user's book" do
    private_book = Book.create!(user: users(:two), name: "Private", total_pages: 1)

    get book_url(private_book)

    assert_response :not_found
  end

  test "shows generating books without a whole-book rerun control for administrators" do
    admin = users(:three)
    admin.update!(admin: true)
    Tutorial.create!(user: admin, eula: true, terms: true, tutorial_complete: true)
    book = Book.create!(user: admin, name: "Generating", total_pages: 1, generation_status: :in_progress)
    sign_in admin

    get book_url(book)

    assert_response :success
    assert_select "#castle_construction"
    assert_select "form[action='#{rerun_generation_admin_book_path(book)}']", count: 0
  end
end
