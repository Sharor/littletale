# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ReconcilePrintOrderSubmissionJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    admin = users(:one)
    admin.update!(admin: true)
    @order = admin.print_orders.create!(
      title: "Uncertain moon",
      language: "en",
      pod_package_id: PrintOrder::POD_PACKAGE_ID,
      workflow_state: "submission_uncertain",
      submission_uuid: SecureRandom.uuid,
      submission_uncertain_at: Time.current
    )
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
  end

  test "matches the exact external id before any retry" do
    client = Object.new
    client.define_singleton_method(:find_print_job_by_external_id) do |external_id|
      { "id" => 552, "external_id" => external_id, "status" => { "name" => "CREATED" } }
    end

    Lulu::Client.stub(:new, client) do
      ReconcilePrintOrderSubmissionJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid, 0
      )
    end

    @order.reload
    assert_equal "552", @order.lulu_print_job_id
    assert_equal "CREATED", @order.provider_status
    assert_equal "submitted", @order.workflow_state
    assert_nil @order.submission_uncertain_at
  end

  test "stops after bounded searches without creating another print job" do
    client = Object.new
    client.define_singleton_method(:find_print_job_by_external_id) { |_| nil }

    Lulu::Client.stub(:new, client) do
      assert_no_enqueued_jobs do
        ReconcilePrintOrderSubmissionJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, @order.submission_uuid,
          ReconcilePrintOrderSubmissionJob::MAX_SEARCHES
        )
      end
    end

    @order.reload
    assert_equal "submission_needs_review", @order.workflow_state
    assert_nil @order.lulu_print_job_id
    assert_match(/could not confirm/, @order.failure_message)
  end
end
