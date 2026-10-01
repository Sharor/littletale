# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class SubmitPrintOrderJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    @previous_host = ENV["LULU_ASSET_HOST"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    ENV["LULU_ASSET_HOST"] = "https://assets.example.test"
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Submitted moon", total_pages: 1, language: "en", generation_status: :completed)
    page = book.pages.create!(text: "A submitted story.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moon")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
    @order.update!(recipient_name: "A Reader", street1: "Story Lane 4", city: "Copenhagen", postcode: "2100",
      country_code: "DK", recipient_email: "reader@example.com", phone_number: "+45 12345678", step: 3)
    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
    @order.reload.update!(
      validation_state: "validated",
      validation_details: {
        "content_revision" => @order.content_revision,
        "checkout_revision" => @order.checkout_revision
      },
      shipping_option: "MAIL",
      shipping_options: [ { "level" => "MAIL", "currency" => "EUR" } ],
      quote: { "currency" => "EUR", "total_cost_incl_tax" => "14.80" },
      quote_revision: @order.checkout_revision,
      quoted_at: Time.current,
      workflow_state: "submitting",
      submission_uuid: SecureRandom.uuid
    )
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
    ENV["LULU_ASSET_HOST"] = @previous_host
  end

  test "submits the exact retained revision once and persists Lulu's id" do
    client = SuccessfulSubmissionClient.new

    Lulu::Client.stub(:new, client) do
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
      )
    end

    @order.reload
    assert_equal "551", @order.lulu_print_job_id
    assert_equal "UNPAID", @order.provider_status
    assert_equal "submitted", @order.workflow_state
    assert_predicate @order.submitted_at, :present?
    assert_equal @order.submission_uuid, client.payload.fetch(:external_id)
    assert_equal 1, client.payload.dig(:line_items, 0, :quantity)
    assert_equal PrintOrder::POD_PACKAGE_ID,
      client.payload.dig(:line_items, 0, :printable_normalization, :pod_package_id)
    assert_equal "assets.example.test",
      URI(client.payload.dig(:line_items, 0, :printable_normalization, :interior, :source_url)).host
  end

  test "a transport timeout becomes uncertain and only enqueues reconciliation" do
    client = Object.new
    client.define_singleton_method(:create_print_job) do |**|
      raise Lulu::Client::RequestError.new(status: 0, details: "The Lulu sandbox did not respond.")
    end

    Lulu::Client.stub(:new, client) do
      assert_enqueued_with(
        job: ReconcilePrintOrderSubmissionJob,
        args: [ @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid, 0 ]
      ) do
        SubmitPrintOrderJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
        )
      end
    end

    @order.reload
    assert_equal "submission_uncertain", @order.workflow_state
    assert_predicate @order.submission_uncertain_at, :present?
    assert_nil @order.lulu_print_job_id
  end

  test "does not submit a stale checkout revision" do
    client = Object.new
    client.define_singleton_method(:create_print_job) { |**| flunk "stale job contacted Lulu" }

    Lulu::Client.stub(:new, client) do
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision + 1, @order.submission_uuid
      )
    end

    assert_nil @order.reload.lulu_print_job_id
  end

  test "a definite provider rejection fails without reconciliation" do
    client = Object.new
    client.define_singleton_method(:create_print_job) do |**|
      raise Lulu::Client::RequestError.new(status: 400, details: { "shipping_address" => [ "Invalid" ] })
    end

    Lulu::Client.stub(:new, client) do
      assert_no_enqueued_jobs do
        SubmitPrintOrderJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
        )
      end
    end

    @order.reload
    assert_equal "submission_failed", @order.workflow_state
    assert_match(/shipping_address: Invalid/, @order.failure_message)
    assert_nil @order.submission_uncertain_at
  end

  class SuccessfulSubmissionClient
    attr_reader :payload

    def create_print_job(**payload)
      @payload = payload
      { "id" => 551, "external_id" => payload.fetch(:external_id), "status" => { "name" => "UNPAID" } }
    end
  end
end
