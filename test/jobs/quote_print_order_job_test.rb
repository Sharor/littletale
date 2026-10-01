# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class QuotePrintOrderJobTest < ActiveJob::TestCase
  setup do
    @previous_flag = ENV["LULU_ORDERS_ENABLED"]
    ENV["LULU_ORDERS_ENABLED"] = "true"
    admin = users(:one)
    admin.update!(admin: true)
    book = admin.books.create!(name: "Quoted moon", total_pages: 1, language: "en", generation_status: :completed)
    page = book.pages.create!(text: "A quoted story.", story_position: 1)
    illustration = page.create_illustration!(original_description: "A moon")
    File.open(Rails.root.join("test/fixtures/files/character.png"), "rb") { |file| illustration.original_image = file }
    illustration.save!
    @order = PrintOrder.start_for!(user: admin, book:)
    @order.update!(recipient_name: "A Reader", street1: "Story Lane 4", city: "Copenhagen", postcode: "2100",
      country_code: "DK", recipient_email: "reader@example.com", phone_number: "+45 12345678", step: 3,
      validation_state: "validated", shipping_options: [ { "level" => "MAIL", "currency" => "EUR" } ])
    PreparePrintOrderJob.perform_now(@order.id, @order.content_revision)
    @order.reload.update!(validation_state: "validated",
      shipping_options: [ { "level" => "MAIL", "currency" => "EUR" } ])
  end

  teardown do
    ENV["LULU_ORDERS_ENABLED"] = @previous_flag
  end

  test "stores a revision-specific quote for an available shipping option" do
    client = Object.new
    client.define_singleton_method(:cost_calculation) do |**|
      { "currency" => "EUR", "total_cost_incl_tax" => "14.80", "total_tax" => "2.96",
        "shipping_cost" => { "total_cost_incl_tax" => "5.00" } }
    end

    Lulu::Client.stub(:new, client) do
      QuotePrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, "MAIL"
      )
    end

    @order.reload
    assert_equal "MAIL", @order.shipping_option
    assert_equal "14.80", @order.quote.fetch("total_cost_incl_tax")
    assert_equal "EUR", @order.quote.fetch("currency")
    assert_equal @order.checkout_revision, @order.quote_revision
    assert_predicate @order.quoted_at, :present?
    assert_equal "quoted", @order.workflow_state
  end

  test "ignores a quote response for a stale checkout revision" do
    client = Object.new
    client.define_singleton_method(:cost_calculation) { |**| raise "should not contact Lulu" }

    Lulu::Client.stub(:new, client) do
      QuotePrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision + 1, "MAIL"
      )
    end

    assert_empty @order.reload.quote
  end

  test "does not persist a quote after submission starts during the provider request" do
    order = @order
    client = Object.new
    client.define_singleton_method(:cost_calculation) do |**|
      order.update!(workflow_state: "submitting", submission_uuid: SecureRandom.uuid)
      { "currency" => "EUR", "total_cost_incl_tax" => "99.00" }
    end

    Lulu::Client.stub(:new, client) do
      QuotePrintOrderJob.perform_now(
        @order.id, @order.content_revision, @order.checkout_revision, "MAIL"
      )
    end

    @order.reload
    assert_equal "submitting", @order.workflow_state
    assert_empty @order.quote
  end
end
