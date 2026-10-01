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
    client = preserve_current_quote(SuccessfulSubmissionClient.new)

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

  test "a duplicate delivery cannot post after the first delivery claims the submission" do
    calls = 0
    nested = false
    order_id = @order.id
    content_revision = @order.content_revision
    checkout_revision = @order.checkout_revision
    submission_uuid = @order.submission_uuid
    client = preserve_current_quote(Object.new)
    client.define_singleton_method(:create_print_job) do |**payload|
      calls += 1
      unless nested
        nested = true
        SubmitPrintOrderJob.perform_now(
          order_id, content_revision, checkout_revision, submission_uuid
        )
      end
      { "id" => 551, "external_id" => payload.fetch(:external_id), "status" => { "name" => "UNPAID" } }
    end

    Lulu::Client.stub(:new, client) do
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
      )
    end

    assert_equal 1, calls
    assert_equal "551", @order.reload.lulu_print_job_id
  end

  test "a redelivery after the provider response reconciles instead of posting again" do
    calls = 0
    client = preserve_current_quote(Object.new)
    client.define_singleton_method(:create_print_job) do |**|
      calls += 1
      {}
    end

    Lulu::Client.stub(:new, client) do
      assert_raises(KeyError) do
        SubmitPrintOrderJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
        )
      end
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
      )
    end

    assert_equal 1, calls
    assert_nil @order.reload.lulu_print_job_id
  end

  test "a changed provider quote requires another confirmation before submission" do
    client = Object.new
    client.define_singleton_method(:cost_calculation) do |**|
      { "currency" => "EUR", "total_cost_incl_tax" => "15.80", "total_tax" => "3.16",
        "shipping_cost" => { "total_cost_incl_tax" => "5.00" } }
    end
    client.define_singleton_method(:create_print_job) { |**| raise "changed quote was submitted" }

    Lulu::Client.stub(:new, client) do
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
      )
    end

    @order.reload
    assert_equal "quote_changed", @order.workflow_state
    assert_equal "15.80", @order.quote.fetch("total_cost_incl_tax")
    assert_nil @order.submission_uuid
    assert_nil @order.submission_attempted_at
    assert_empty @order.submission_attempts
  end

  test "a transport timeout becomes uncertain and only enqueues reconciliation" do
    client = preserve_current_quote(Object.new)
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

  test "an ambiguous provider response becomes uncertain and only enqueues reconciliation" do
    client = preserve_current_quote(Object.new)
    client.define_singleton_method(:create_print_job) do |**|
      raise Lulu::Client::RequestError.new(status: 503, details: "Service unavailable")
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

    assert_equal "submission_uncertain", @order.reload.workflow_state
    assert_predicate @order.submission_uncertain_at, :present?
  end

  test "does not submit a stale checkout revision" do
    client = preserve_current_quote(Object.new)
    client.define_singleton_method(:create_print_job) { |**| flunk "stale job contacted Lulu" }

    Lulu::Client.stub(:new, client) do
      SubmitPrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision + 1, @order.submission_uuid
      )
    end

    assert_nil @order.reload.lulu_print_job_id
  end

  test "a definite provider rejection fails without another submission" do
    client = preserve_current_quote(Object.new)
    client.define_singleton_method(:create_print_job) do |**|
      raise Lulu::Client::RequestError.new(status: 400, details: { "shipping_address" => [ "Invalid" ] })
    end

    Lulu::Client.stub(:new, client) do
      assert_enqueued_with(job: ReconcilePrintOrderSubmissionJob) do
        SubmitPrintOrderJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid
        )
      end
    end

    @order.reload
    assert_equal "submission_failed", @order.workflow_state
    assert_match(/shipping_address: Invalid/, @order.failure_message)
    assert_nil @order.submission_uncertain_at
    assert_equal "rejected", @order.submission_attempts.last.fetch("outcome")
  end

  class SuccessfulSubmissionClient
    attr_reader :payload

    def create_print_job(**payload)
      @payload = payload
      { "id" => 551, "external_id" => payload.fetch(:external_id), "status" => { "name" => "UNPAID" } }
    end
  end

  private

  def preserve_current_quote(client)
    quote = @order.quote.deep_dup
    client.define_singleton_method(:cost_calculation) { |**| quote }
    client
  end
end
