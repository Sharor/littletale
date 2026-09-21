# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Payments::StripeGatewayTest < ActiveSupport::TestCase
  test "retrieves the account belonging to the API key" do
    arguments = nil
    response = { "id" => "acct_expected" }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::Account.stub(:retrieve, replacement) do
      Payments::StripeGateway.new.retrieve_account
    end

    assert_empty arguments
    assert_equal response, result
  end

  test "retrieves the product with its default price expanded" do
    arguments = nil
    response = { "id" => BookPurchase::PRODUCT_ID, "default_price" => { "id" => "price_book" } }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::Product.stub(:retrieve, replacement) do
      Payments::StripeGateway.new.retrieve_product(BookPurchase::PRODUCT_ID)
    end

    assert_equal [ { id: BookPurchase::PRODUCT_ID, expand: [ "default_price" ] } ], arguments
    assert_equal response, result
  end

  test "retrieves the checkout session with line item products expanded" do
    arguments = nil
    response = { "id" => "cs_test_book" }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::Checkout::Session.stub(:retrieve, replacement) do
      Payments::StripeGateway.new.retrieve_checkout_session("cs_test_book")
    end

    assert_equal [ { id: "cs_test_book", expand: [ "line_items.data.price.product" ] } ], arguments
    assert_equal response, result
  end

  test "retrieves an invoice with price products expanded" do
    arguments = nil
    response = { "id" => "in_monthly" }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::Invoice.stub(:retrieve, replacement) do
      Payments::StripeGateway.new.retrieve_invoice("in_monthly")
    end

    assert_equal [ { id: "in_monthly" } ], arguments
    assert_equal response, result
  end

  test "creates a Stripe billing portal session" do
    arguments = nil
    response = { "url" => "https://billing.stripe.test/session" }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::BillingPortal::Session.stub(:create, replacement) do
      Payments::StripeGateway.new.create_billing_portal_session(
        customer: "cus_portal",
        return_url: "https://example.test/settings"
      )
    end

    assert_equal [ { customer: "cus_portal", return_url: "https://example.test/settings" } ], arguments
    assert_equal response, result
  end

  test "retrieves a subscription with its price product expanded" do
    arguments = nil
    response = { "id" => "sub_monthly" }
    replacement = lambda do |*received|
      arguments = received
      response
    end

    result = Stripe::Subscription.stub(:retrieve, replacement) do
      Payments::StripeGateway.new.retrieve_subscription("sub_monthly")
    end

    assert_equal [ { id: "sub_monthly", expand: [ "items.data.price.product" ] } ], arguments
    assert_equal response, result
  end
end
