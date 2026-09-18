# frozen_string_literal: true

module Payments
  class FulfillCheckout
    class InvalidSession < StandardError; end

    def self.call(session:)
      new(session).call
    end

    def initialize(session)
      @session = session.respond_to?(:to_hash) ? session.to_hash.deep_stringify_keys : session.deep_stringify_keys
    end

    def call
      purchase = BookPurchase.find(metadata.fetch("purchase_id"))
      validate!(purchase)
      purchase.fulfill!(
        checkout_session_id: session.fetch("id"),
        payment_intent_id: identifier(session["payment_intent"]),
        stripe_customer_id: identifier(session["customer"]),
        price_id: identifier(price),
        amount_total: session.fetch("amount_total"),
        currency: session.fetch("currency")
      )
      true
    rescue ActiveRecord::RecordNotFound, KeyError, TypeError, ArgumentError => error
      raise InvalidSession, error.message
    end

    private

    attr_reader :session

    def metadata
      session.fetch("metadata")
    end

    def line_item
      items = session.dig("line_items", "data")
      raise InvalidSession, "Checkout must contain exactly one line item" unless items.is_a?(Array) && items.one?

      items.first
    end

    def price
      line_item.fetch("price")
    end

    def validate!(purchase)
      checks = [
        session["mode"] == "payment",
        session["payment_status"] == "paid",
        session["id"] == purchase.stripe_checkout_session_id,
        session["livemode"] == purchase.livemode,
        session["amount_total"] == purchase.amount_total,
        session["currency"] == purchase.currency,
        metadata["purchase_id"] == purchase.id.to_s,
        metadata["user_id"] == purchase.user_id.to_s,
        metadata["product_id"] == BookPurchase::PRODUCT_ID,
        line_item["quantity"] == 1,
        identifier(price) == purchase.price_id,
        identifier(price["product"]) == BookPurchase::PRODUCT_ID,
        price["type"] == "one_time",
        identifier(session["customer"]).present?,
        identifier(session["payment_intent"]).present?
      ]
      raise InvalidSession, "Checkout session does not match the purchase" unless checks.all?
    end

    def identifier(value)
      value.is_a?(Hash) ? value["id"] : value
    end
  end
end
