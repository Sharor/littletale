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
end
