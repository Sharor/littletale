# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class RefreshPrintOrderStatusJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    admin = users(:one)
    admin.update!(admin: true)
    @order = admin.print_orders.create!(
      title: "Tracked moon",
      language: "en",
      pod_package_id: PrintOrder::POD_PACKAGE_ID,
      workflow_state: "submitted",
      submission_uuid: SecureRandom.uuid,
      lulu_print_job_id: "551",
      provider_status: "CREATED",
      submitted_at: Time.current
    )
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
  end

  test "persists status and polls nonterminal states with a bound" do
    client = Object.new
    client.define_singleton_method(:print_job_status) do |_id|
      { "name" => "PRODUCTION_READY", "changed" => "2026-10-01T12:00:00Z" }
    end

    Lulu::Client.stub(:new, client) do
      assert_enqueued_with(job: RefreshPrintOrderStatusJob, args: [ @order.id, 1 ]) do
        RefreshPrintOrderStatusJob.perform_now(@order.id, 0)
      end
    end

    assert_equal "PRODUCTION_READY", @order.reload.provider_status
    assert_predicate @order.last_status_checked_at, :present?
  end

  test "stops polling when the sandbox order is unpaid" do
    client = Object.new
    client.define_singleton_method(:print_job_status) do |_id|
      { "name" => "UNPAID", "changed" => "2026-10-01T12:00:00Z", "message" => "Payment required" }
    end

    Lulu::Client.stub(:new, client) do
      assert_no_enqueued_jobs { RefreshPrintOrderStatusJob.perform_now(@order.id, 0) }
    end

    assert_equal "UNPAID", @order.reload.provider_status
  end

  test "stops after the bounded status poll limit" do
    client = Object.new
    client.define_singleton_method(:print_job_status) do |_id|
      { "name" => "PRODUCTION_READY", "changed" => "2026-10-01T12:00:00Z" }
    end

    Lulu::Client.stub(:new, client) do
      assert_no_enqueued_jobs do
        RefreshPrintOrderStatusJob.perform_now(@order.id, RefreshPrintOrderStatusJob::MAX_POLLS)
      end
    end

    assert_equal "PRODUCTION_READY", @order.reload.provider_status
  end
end
