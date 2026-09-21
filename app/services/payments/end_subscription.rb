# frozen_string_literal: true

module Payments
  class EndSubscription
    class InvalidSubscription < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(subscription:)
      @stripe_subscription = if subscription.respond_to?(:to_hash)
        subscription.to_hash.deep_stringify_keys
      else
        subscription.deep_stringify_keys
      end
    end

    def call
      local = UserSubscription.find_by!(stripe_subscription_id: stripe_subscription.fetch("id"))
      validate!(local)
      ended_at = stripe_subscription["ended_at"] || stripe_subscription["current_period_end"] || Time.current.to_i
      local.end!(ended_at: Time.zone.at(ended_at))
      true
    rescue ActiveRecord::RecordNotFound, KeyError, TypeError, ArgumentError => error
      raise InvalidSubscription, error.message
    end

    private

    attr_reader :stripe_subscription

    def validate!(local)
      items = stripe_subscription.dig("items", "data")
      prices = Array(items).filter_map { |item| item["price"] }
      valid_price = prices.one? && identifier(prices.first["product"]) == UserSubscription::PRODUCT_ID &&
        identifier(prices.first) == local.price_id
      checks = [
        stripe_subscription["status"] == "canceled",
        stripe_subscription["livemode"] == local.livemode,
        identifier(stripe_subscription["customer"]) == local.stripe_customer_id,
        local.user.stripe_customer_id == local.stripe_customer_id,
        local.product_id == UserSubscription::PRODUCT_ID,
        valid_price
      ]
      raise InvalidSubscription, "Stripe subscription does not match the local subscription" unless checks.all?
    end

    def identifier(value)
      value.is_a?(Hash) ? value["id"] : value
    end
  end
end
