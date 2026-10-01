# frozen_string_literal: true

require "test_helper"

class PrintOrdersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    @admin.tutorial.update!(terms: true)
    @book = create_eligible_book(@admin)
    sign_in @admin
  end

  test "enabled admins can open orders from navigation" do
    with_lulu_orders_enabled do
      get "/orders"

      assert_response :success
      assert_select "main h1", "Book orders"
      assert_select "aside nav a[href='/orders']", text: /Orders/
      assert_select "header nav a[href='/orders'][aria-label='Orders']"
    end
  end

  test "enabled ordinary users cannot see or open orders" do
    @admin.update!(admin: false)

    with_lulu_orders_enabled do
      get "/orders"
      assert_response :not_found

      get books_path
      assert_response :success
      assert_select "a[href='/orders']", count: 0
    end
  end

  test "disabled orders are hidden and inaccessible to admins" do
    without_lulu_orders_enabled do
      get "/orders"
      assert_response :not_found

      get books_path
      assert_response :success
      assert_select "a[href='/orders']", count: 0
    end
  end

  test "enabled orders still require authentication" do
    sign_out @admin

    with_lulu_orders_enabled do
      get "/orders"

      assert_redirected_to new_user_session_path
    end
  end

  test "an admin chooses a completed book and gets a retained draft" do
    with_lulu_orders_enabled do
      get "/orders/new"

      assert_response :success
      assert_select "form[action='/orders']" do
        assert_select "input[type='radio'][name='book_id'][value='#{@book.id}']"
        assert_select "a[href='#{book_path(@book)}']", text: "Read book"
      end

      assert_difference("PrintOrder.count", 1) do
        post "/orders", params: { book_id: @book.id }
      end
    end

    order = PrintOrder.order(:id).last
    assert_redirected_to "/orders/#{order.id}"
    assert_equal @book.name, order.title
    assert_equal @book.current_pages.pluck(:text), order.print_order_pages.pluck(:text)

    with_lulu_orders_enabled do
      follow_redirect!
    end
    assert_select "a[href='/orders/#{order.id}/read']", text: "Read retained book"
    assert_select "a[href='/orders/#{order.id}/address']", text: "Continue to delivery"
  end

  test "the retained reader returns to the saved order step" do
    order = PrintOrder.start_for!(user: @admin, book: @book)

    with_lulu_orders_enabled do
      get "/orders/#{order.id}/read"
    end

    assert_response :success
    assert_select "#storybook h1", order.title
    assert_select ".story-body", "Once upon a print order."
    assert_select "a[href='/orders/#{order.id}']", text: "Back to order"
  end

  test "the delivery step preserves errors and advances only with a complete address" do
    order = PrintOrder.start_for!(user: @admin, book: @book)

    with_lulu_orders_enabled do
      patch "/orders/#{order.id}/address", params: {
        print_order: { recipient_name: "A Reader", country_code: "DK" }
      }
    end

    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /Street1 can't be blank/
    assert_select "input[name='print_order[recipient_name]'][value='A Reader']"
    assert_equal 1, order.reload.step

    with_lulu_orders_enabled do
      patch "/orders/#{order.id}/address", params: {
        print_order: {
          recipient_name: "A Reader",
          street1: "Story Lane 4",
          street2: "2nd floor",
          city: "Copenhagen",
          postcode: "2100",
          country_code: "dk",
          recipient_email: "reader@example.com",
          phone_number: "+45 12345678"
        }
      }
    end

    assert_redirected_to "/orders/#{order.id}/options"
    assert_equal 3, order.reload.step
    assert_equal "DK", order.country_code
    assert_equal "Story Lane 4", order.street1
  end

  test "the print step shows the retained book address and single booklet format" do
    order = addressed_order

    with_lulu_orders_enabled do
      get "/orders/#{order.id}/options"
    end

    assert_response :success
    assert_select "h1", "Choose print format"
    assert_select "a[href='/orders/#{order.id}/read']", text: "Read retained book"
    assert_select "[data-pod-package-id='#{PrintOrder::POD_PACKAGE_ID}']", text: /5 × 8.*Premium color.*Saddle stitch/m
    assert_select "address", text: /Story Lane 4.*2100 Copenhagen/m
  end

  test "an admin cannot access another admin's order" do
    other_admin = users(:two)
    other_admin.update!(admin: true, encrypted_password: Devise.friendly_token[0, 20])
    other_admin.tutorial.update!(terms: true)
    order = PrintOrder.start_for!(user: other_admin, book: create_eligible_book(other_admin))
    sign_in @admin

    with_lulu_orders_enabled do
      [ "/orders/#{order.id}/address", "/orders/#{order.id}/options", "/orders/#{order.id}/read" ].each do |path|
        sign_in @admin
        get path
        assert_response :not_found
      end
    end
  end

  test "the print step queues revision-specific PDF preparation" do
    order = addressed_order

    with_lulu_orders_enabled do
      assert_enqueued_with(job: PreparePrintOrderJob, args: [ order.id, order.content_revision ]) do
        post "/orders/#{order.id}/prepare"
      end
    end

    assert_redirected_to "/orders/#{order.id}/options"
    assert_equal "preparing", order.reload.workflow_state
  end

  test "an admin can preview prepared PDFs and required blank pages" do
    order = addressed_order
    with_lulu_orders_enabled do
      PreparePrintOrderJob.perform_now(order.id, order.content_revision)
      get "/orders/#{order.id}/options"
    end

    assert_response :success
    assert_select "[data-print-page-count='4']", text: /4 interior pages.*1 binding-required blank page/m
    assert_select "a[href='/orders/#{order.id}/interior_pdf']", text: "Preview interior PDF"
    assert_select "a[href='/orders/#{order.id}/cover_pdf']", text: "Preview cover PDF"

    with_lulu_orders_enabled do
      get "/orders/#{order.id}/interior_pdf"
    end
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF-")
  end

  test "prepared files can be queued for revision-specific Lulu validation" do
    order = addressed_order
    with_lulu_orders_enabled do
      PreparePrintOrderJob.perform_now(order.id, order.content_revision)
    end

    with_lulu_asset_host do
      with_lulu_orders_enabled do
        assert_enqueued_with(
          job: ValidatePrintOrderJob,
          args: [ order.id, order.content_revision, order.checkout_revision, 0 ]
        ) { post "/orders/#{order.id}/validate_files" }
      end
    end

    assert_redirected_to "/orders/#{order.id}/options"
    assert_equal "validating", order.reload.validation_state
  end

  test "validation stays unavailable until a public HTTPS asset host is configured" do
    order = addressed_order
    with_lulu_orders_enabled do
      PreparePrintOrderJob.perform_now(order.id, order.content_revision)
      assert_no_enqueued_jobs { post "/orders/#{order.id}/validate_files" }
    end

    assert_redirected_to "/orders/#{order.id}/options"
    with_lulu_orders_enabled { follow_redirect! }
    assert_select "[data-lulu-readiness='missing-asset-host']", text: /public HTTPS asset host/
  end

  test "validated shipping choices can be queued for a revision-specific quote" do
    order = quoted_ready_order

    with_lulu_orders_enabled do
      assert_enqueued_with(
        job: QuotePrintOrderJob,
        args: [ order.id, order.content_revision, order.checkout_revision, "MAIL" ]
      ) { post "/orders/#{order.id}/quote", params: { shipping_option: "MAIL" } }
    end

    assert_redirected_to "/orders/#{order.id}/options"
    assert_equal "quoting", order.reload.workflow_state
    assert_equal "MAIL", order.shipping_option
  end

  test "the print step renders shipping options and the current provider quote" do
    order = quoted_ready_order
    order.update!(
      shipping_option: "MAIL",
      quote: {
        "currency" => "EUR", "total_cost_incl_tax" => "14.80", "total_tax" => "2.96",
        "shipping_cost" => { "total_cost_incl_tax" => "5.00" }
      },
      quote_revision: order.checkout_revision,
      quoted_at: Time.current,
      workflow_state: "quoted"
    )

    with_lulu_asset_host do
      with_lulu_orders_enabled { get "/orders/#{order.id}/options" }
    end

    assert_response :success
    assert_select "[data-shipping-option='MAIL']", text: /Mail.*4.25 EUR.*7–12 business days/m
    assert_select "[data-print-order-total='14.80']", text: /14.80 EUR/
    assert_select "[data-print-order-tax='2.96']", text: /2.96 EUR/
  end

  private

  def with_lulu_orders_enabled
    previous = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    yield
  ensure
    ENV["LULU_ORDERS_ENABLED"] = previous
  end

  def without_lulu_orders_enabled
    previous = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "false"
    yield
  ensure
    ENV["LULU_ORDERS_ENABLED"] = previous
  end

  def with_lulu_asset_host
    previous = ENV["LULU_ASSET_HOST"]
    ENV["LULU_ASSET_HOST"] = "https://assets.example.test"
    yield
  ensure
    ENV["LULU_ASSET_HOST"] = previous
  end

  def create_eligible_book(user)
    book = user.books.create!(name: "Printable moon", total_pages: 1, language: "en",
      generation_status: :completed)
    page = book.pages.create!(text: "Once upon a print order.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moon over a small house")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") do |file|
      illustration.original_image = file
    end
    illustration.save!
    book
  end

  def addressed_order
    PrintOrder.start_for!(user: @admin, book: @book).tap do |order|
      order.update!(
        recipient_name: "A Reader",
        street1: "Story Lane 4",
        city: "Copenhagen",
        postcode: "2100",
        country_code: "DK",
        recipient_email: "reader@example.com",
        phone_number: "+45 12345678",
        step: 3
      )
    end
  end

  def quoted_ready_order
    addressed_order.tap do |order|
      with_lulu_orders_enabled { PreparePrintOrderJob.perform_now(order.id, order.content_revision) }
      order.reload.update!(
        validation_state: "validated",
        validation_details: {
          "content_revision" => order.content_revision,
          "checkout_revision" => order.checkout_revision,
          "interior_status" => "NORMALIZED",
          "cover_status" => "NORMALIZED"
        },
        shipping_options: [
          {
            "level" => "MAIL", "currency" => "EUR", "cost_excl_tax" => "4.25",
            "total_days_min" => 7, "total_days_max" => 12
          }
        ],
        workflow_state: "selecting_shipping"
      )
    end
  end
end
