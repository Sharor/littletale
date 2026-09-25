# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

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
    assert_select "main h1", "Current Library"
    assert_select "h3", text: @book.name
    assert_select "h3", text: private_book.name, count: 0
    assert_select "main a[href='#{characters_path}']", text: /Make a new book/
    assert_select "main a[href='#{book_path(@book)}'][aria-label=?]", "Read #{@book.name}", text: "Read"
  end

  test "index lists only categories populated by the signed-in user's books" do
    @book.update_columns(categories: [ "Adventure" ])
    @user.books.create!(name: "Magic school", total_pages: 1, categories: [ "Fantasy" ])
    Book.create!(user: users(:two), name: "Private romance", total_pages: 1, categories: [ "Romance" ])

    get books_url

    assert_response :success
    assert_select "form.library-category-filter" do
      assert_select "option[value='']", text: "All categories"
      assert_select "option[value='Adventure']", text: "Adventure"
      assert_select "option[value='Fantasy']", text: "Fantasy"
      assert_select "option[value='Romance']", count: 0
    end
  end

  test "index filters owned books by category" do
    @book.update_columns(categories: [ "Adventure", "Fantasy" ])
    other_book = @user.books.create!(name: "Quiet birthday", total_pages: 1, categories: [ "Birthdays" ])

    get books_url(category: "Adventure")

    assert_response :success
    assert_select "select[name='category'] option[value='Adventure'][selected]"
    assert_select "main h3", text: @book.name
    assert_select "main h3", text: other_book.name, count: 0
  end

  test "category filtering leaves claimed gifts visible" do
    @book.update_columns(categories: [ "Adventure" ])
    gift = BookGift.create!(
      sender: users(:two),
      recipient: @user,
      recipient_name: "Reader",
      recipient_email: "reader@gmail.com",
      sender_callname: "Sender",
      message: "Enjoy this story",
      language: "en",
      title: "Gifted forest",
      token_digest: SecureRandom.hex(32),
      issuance_key: SecureRandom.uuid,
      invitation_token_ciphertext: "encrypted-token",
      claimed_at: Time.current
    )

    get books_url(category: "Adventure")

    assert_response :success
    assert_select "main h3", text: @book.name
    assert_select "main h3", text: gift.title
  end

  test "empty library preserves the create book tutorial entry point" do
    @user.books.destroy_all

    get books_url

    assert_response :success
    assert_select "main h1", "Current Library"
    assert_select "main a.new_book_tutorial[href='#{characters_path}']", text: /Make a new book/, count: 1
    assert_select "main h3", count: 0
  end

  test "library renders accessible navigation for mobile devices in either orientation" do
    get books_url, headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1" }

    assert_response :success
    # CSS selects the appropriate navigation at the current viewport width.
    assert_select "aside nav a[href='#{books_path}']", text: /Home Dashboard/
    assert_select "header nav a[href='#{books_path}'][aria-label='Home Dashboard']"
  end

  test "new renders the page limit for the user's tier" do
    get new_book_url

    assert_response :success
    assert_select "form[action='#{books_path}']"
    assert_select "input[name='book[total_pages]'][max='5']"
    assert_select "strong", "5 pages"
  end

  test "new books inherit the user's generation preferences" do
    @user.update!(language: "da", reader_age: 6)

    get new_book_url

    assert_response :success
    assert_select "select[name='book[language]'] option[value='da'][selected]"
    assert_select "input[name='book[reader_age]'][value='6']"
  end

  test "new presents every art style with western book style selected" do
    get new_book_url

    assert_response :success
    assert_select "section[data-controller='art-style-picker']" do
      assert_select "h2#book-art-style-heading.fable-form-label", text: "Choose an art style"
      assert_select "fieldset[aria-labelledby='book-art-style-heading']", count: 1
      assert_select "input[type='radio'][name='book[art_style]']", count: 12
      assert_select "input[type='radio'][name='book[art_style]'][value='western_book_style'][checked]", count: 1
      assert_select "img[data-art-style-picker-target='preview']", count: 1
      assert_select "img[alt*='Western Book Style']", minimum: 1
      assert_select "label", text: /Claymation \/ Plasticine/
      assert_select "label", text: /Superhero Comic/
    end
  end

  test "create clamps pages to the tier limit and queues generation" do
    assert_difference("Book.count", 1) do
      assert_enqueued_with(job: GenerateBookJob) do
        post books_url, params: { book: { name: "A new tale", plot: "Adventure", total_pages: 12 } }
      end
    end

    book = Book.find_by!(name: "A new tale", user: @user)
    assert_equal 5, book.total_pages
    assert_equal book, @user.trial_book_reservations.held.find_by!(book: book).book
    assert_redirected_to book_url(book, format: :html)
  end

  test "create persists book generation preferences" do
    post books_url, params: { book: { name: "Dansk eventyr", plot: "En skovtur", total_pages: 3,
      language: "da", reader_age: 8 } }

    book = @user.books.find_by!(name: "Dansk eventyr")
    assert_equal "da", book.language
    assert_equal 8, book.reader_age
  end

  test "create persists the selected art style" do
    post books_url, params: { book: { name: "Ink adventure", plot: "A city rescue", total_pages: 3,
      art_style: "comic_book" } }

    assert_equal "comic_book", @user.books.find_by!(name: "Ink adventure").art_style
  end

  test "create rejects an unknown art style and renders the form safely" do
    assert_no_difference("Book.count") do
      post books_url, params: { book: { name: "Invalid style", plot: "A city rescue", total_pages: 3,
        art_style: "unknown_style" } }
    end

    assert_response :unprocessable_content
    assert_select "section[data-controller='art-style-picker']"
    assert_select "input[type='radio'][value='western_book_style'][checked]"
  end

  test "create rejects a fourth held trial book without queueing generation" do
    3.times do |number|
      reserved = @user.books.create!(name: "Reserved #{number}", total_pages: 1)
      TrialBookReservation.reserve_for!(reserved)
    end

    assert_no_difference("Book.count") do
      assert_no_enqueued_jobs only: GenerateBookJob do
        post books_url, params: { book: { name: "Fourth book", plot: "Adventure", total_pages: 1 } }
      end
    end

    assert_response :unprocessable_content
    assert_select "li", /three trial books/
  end

  test "a queue enqueue failure releases the newly reserved slot" do
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    assert_difference("Book.count", 1) do
      GenerateBookJob.stub :perform_later, failed_job do
        post books_url, params: { book: { name: "Unqueued book", plot: "Adventure", total_pages: 1 } }
      end
    end

    book = @user.books.find_by!(name: "Unqueued book")
    assert_predicate book, :failed?
    assert_equal "book_enqueue_failed", book.generation_failure.fetch("type")
    assert_equal "released", book.trial_book_reservations.last.status
    assert_equal 3, @user.trial_books_remaining
  end

  test "a raised queue enqueue error releases the newly reserved slot" do
    enqueue_error = SolidQueue::Job::EnqueueError.new("queue database unavailable")

    assert_difference("Book.count", 1) do
      GenerateBookJob.stub :perform_later, ->(*) { raise enqueue_error } do
        post books_url, params: { book: { name: "Queue error book", plot: "Adventure", total_pages: 1 } }
      end
    end

    book = @user.books.find_by!(name: "Queue error book")
    assert_redirected_to book_url(book, format: :html)
    assert_predicate book, :failed?
    assert_equal "book_enqueue_failed", book.generation_failure.fetch("type")
    assert_equal "released", book.trial_book_reservations.last.status
    assert_equal 3, @user.trial_books_remaining
  end

  test "paid users create books without trial reservations" do
    grant_paid_bundle

    assert_difference("Book.count", 1) do
      post books_url, params: { book: { name: "Paid book", plot: "Adventure", total_pages: 6 } }
    end

    assert_empty @user.trial_book_reservations
    assert_equal 0, @user.reload.available_book_credits
    assert_predicate @user.book_credit_reservations.held, :exists?
  end

  test "paid users without a book credit cannot create a book" do
    @user.update!(tier: "basic")

    assert_no_difference("Book.count") do
      assert_no_enqueued_jobs only: GenerateBookJob do
        post books_url, params: { book: { name: "Unfunded book", plot: "Adventure", total_pages: 1 } }
      end
    end

    assert_response :payment_required
  end

  test "a paid queue handoff failure returns its book credit" do
    grant_paid_bundle
    failed_job = Struct.new(:successfully_enqueued?).new(false)

    GenerateBookJob.stub :perform_later, failed_job do
      post books_url, params: { book: { name: "Paid queue failure", plot: "Adventure", total_pages: 1 } }
    end

    book = @user.books.find_by!(name: "Paid queue failure")
    assert_predicate book, :failed?
    assert_equal "released", book.book_credit_reservations.last.status
    assert_match(/book credit was released/i, book.generation_failure.fetch("message"))
    assert_equal 1, @user.reload.available_book_credits
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

  private

  def grant_paid_bundle
    purchase = @user.book_purchases.create!(status: "pending", product_id: BookPurchase::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid, livemode: false)
    purchase.fulfill!(checkout_session_id: "cs_#{SecureRandom.hex}", payment_intent_id: "pi_#{SecureRandom.hex}",
      stripe_customer_id: "cus_books_controller_#{@user.id}", price_id: "price_test",
      amount_total: 2500, currency: "dkk")
  end
end
