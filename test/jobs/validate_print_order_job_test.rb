# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ValidatePrintOrderJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    @previous_host = ENV["LULU_ASSET_HOST"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    ENV["LULU_ASSET_HOST"] = "https://assets.example.test"
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Validated moon", total_pages: 1, language: "en", generation_status: :completed)
    page = book.pages.create!(text: "A printable story.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moon")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
    @order.update!(recipient_name: "A Reader", street1: "Story Lane 4", city: "Copenhagen", postcode: "2100",
      country_code: "DK", recipient_email: "reader@example.com", phone_number: "+45 12345678", step: 3)
    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
    ENV["LULU_ASSET_HOST"] = @previous_host
  end

  test "starts validation, polls boundedly, and stores shipping options after both files pass" do
    client = FakeValidationClient.new
    args = [ @order.id, @order.content_revision, @order.checkout_revision, 0 ]

    Lulu::Client.stub(:new, client) do
      assert_enqueued_with(
        job: ValidatePrintOrderJob,
        args: [ @order.id, @order.content_revision, @order.checkout_revision, 1 ]
      ) { ValidatePrintOrderJob.perform_now(*args) }
    end

    @order.reload
    assert_equal "validating", @order.validation_state
    assert_equal "10.250", @order.cover_dimensions.fetch("width")
    assert_equal 41, @order.validation_details.fetch("interior_id")
    assert_equal 42, @order.validation_details.fetch("cover_id")

    clear_enqueued_jobs
    Lulu::Client.stub(:new, client) do
      ValidatePrintOrderJob.perform_now(@order.id, @order.content_revision, @order.checkout_revision, 1)
    end

    @order.reload
    assert_equal "validated", @order.validation_state
    assert_equal "selecting_shipping", @order.workflow_state
    assert_equal [ "MAIL", "EXPRESS" ], @order.shipping_options.pluck("level")
    assert_nil @order.failure_message
  end

  test "does not contact Lulu when the checkout revision is stale" do
    client = FakeValidationClient.new

    Lulu::Client.stub(:new, client) do
      ValidatePrintOrderJob.perform_now(@order.id, @order.content_revision, @order.checkout_revision + 1, 0)
    end

    assert_empty client.calls
    assert_equal "not_started", @order.reload.validation_state
  end

  test "does not persist validation after submission starts during the provider request" do
    client = FakeValidationClient.new
    order = @order
    client.define_singleton_method(:create_interior_validation) do |**|
      order.update!(workflow_state: "submitting", submission_uuid: SecureRandom.uuid)
      { "id" => 41, "status" => "NORMALIZING", "errors" => [] }
    end

    Lulu::Client.stub(:new, client) do
      ValidatePrintOrderJob.perform_now(@order.id, @order.content_revision, @order.checkout_revision, 0)
    end

    @order.reload
    assert_equal "submitting", @order.workflow_state
    assert_equal "not_started", @order.validation_state
    assert_empty @order.validation_details
  end

  test "fails visibly after the bounded validation poll limit" do
    client = FakeValidationClient.new

    Lulu::Client.stub(:new, client) do
      assert_no_enqueued_jobs do
        ValidatePrintOrderJob.perform_now(
          @order.id, @order.content_revision, @order.checkout_revision, ValidatePrintOrderJob::MAX_POLLS
        )
      end
    end

    @order.reload
    assert_equal "failed", @order.validation_state
    assert_match(/did not finish validating/, @order.failure_message)
  end

  test "surfaces provider PDF validation errors" do
    @order.update!(
      validation_state: "validating",
      validation_details: { "interior_id" => 41, "cover_id" => 42 }
    )
    client = FakeValidationClient.new
    client.define_singleton_method(:interior_validation) do |id|
      { "id" => id, "status" => "ERROR", "errors" => [
        "Trim size is invalid at https://assets.example.test/private-token for reader@example.com."
      ] }
    end

    Lulu::Client.stub(:new, client) do
      ValidatePrintOrderJob.perform_now(@order.id, @order.content_revision, @order.checkout_revision, 1)
    end

    @order.reload
    assert_equal "failed", @order.validation_state
    assert_match(/interior: Trim size is invalid/, @order.failure_message)
    assert_not_includes @order.failure_message, "private-token"
    assert_not_includes @order.failure_message, "reader@example.com"
  end

  class FakeValidationClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def create_interior_validation(**)
      calls << :create_interior
      { "id" => 41, "status" => "NORMALIZING", "errors" => [] }
    end

    def cover_dimensions(**)
      calls << :cover_dimensions
      { "width" => "10.250", "height" => "8.250", "unit" => "inch" }
    end

    def create_cover_validation(**)
      calls << :create_cover
      { "id" => 42, "status" => "NORMALIZING", "errors" => [] }
    end

    def interior_validation(id)
      calls << [ :interior_validation, id ]
      { "id" => id, "status" => "NORMALIZED", "errors" => [] }
    end

    def cover_validation(id)
      calls << [ :cover_validation, id ]
      { "id" => id, "status" => "NORMALIZED", "errors" => [] }
    end

    def shipping_options(**)
      calls << :shipping_options
      [
        { "level" => "MAIL", "currency" => "EUR", "cost_excl_tax" => "4.25", "total_days_min" => 7, "total_days_max" => 12 },
        { "level" => "EXPRESS", "currency" => "EUR", "cost_excl_tax" => "12.00", "total_days_min" => 2, "total_days_max" => 4 }
      ]
    end
  end
end
