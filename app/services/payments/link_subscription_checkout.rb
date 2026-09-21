# frozen_string_literal: true

module Payments
  class LinkSubscriptionCheckout
    class InvalidSession < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(session:)
      @session = session.respond_to?(:to_hash) ? session.to_hash.deep_stringify_keys : session.deep_stringify_keys
    end

    def call
      subscription = UserSubscription.find(metadata.fetch("user_subscription_id"))
      validate!(subscription)
      customer_id = identifier(session["customer"])
      stripe_subscription_id = identifier(session["subscription"])
      subscription.with_lock do
        subscription.update!(
          stripe_subscription_id: stripe_subscription_id,
          stripe_customer_id: customer_id
        )
        subscription.user.with_lock do
          subscription.user.update!(stripe_customer_id: customer_id)
        end
      end
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

    def validate!(subscription)
      customer_id = identifier(session["customer"])
      stripe_subscription_id = identifier(session["subscription"])
      checks = [
        session["mode"] == "subscription",
        session["id"] == subscription.stripe_checkout_session_id,
        session["livemode"] == subscription.livemode,
        subscription.product_id == UserSubscription::PRODUCT_ID,
        metadata["user_subscription_id"] == subscription.id.to_s,
        metadata["user_id"] == subscription.user_id.to_s,
        metadata["product_id"] == UserSubscription::PRODUCT_ID,
        line_item["quantity"] == 1,
        identifier(price) == subscription.price_id,
        identifier(price["product"]) == UserSubscription::PRODUCT_ID,
        price["type"] == "recurring",
        customer_id.present?,
        stripe_subscription_id.present?,
        subscription.stripe_customer_id.blank? || subscription.stripe_customer_id == customer_id,
        subscription.stripe_subscription_id.blank? || subscription.stripe_subscription_id == stripe_subscription_id,
        subscription.user.stripe_customer_id.blank? || subscription.user.stripe_customer_id == customer_id
      ]
      raise InvalidSession, "Checkout session does not match the subscription" unless checks.all?
    end

    def identifier(value)
      value.is_a?(Hash) ? value["id"] : value
    end
  end
end
