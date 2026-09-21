# frozen_string_literal: true

module Payments
  class SyncSubscription
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
      return EndSubscription.call(subscription: stripe_subscription) if stripe_subscription["status"] == "canceled"

      attributes = {
        status: stripe_subscription.fetch("status"),
        cancel_at_period_end: stripe_subscription["cancel_at_period_end"] || false
      }
      attributes[:current_period_start] = Time.zone.at(period_start) if period_start
      attributes[:current_period_end] = Time.zone.at(period_end) if period_end
      local.update!(attributes)
      true
    rescue ActiveRecord::RecordNotFound, KeyError, TypeError, ArgumentError => error
      raise InvalidSubscription, error.message
    end

    private

    attr_reader :stripe_subscription

    def item
      items = stripe_subscription.dig("items", "data")
      raise InvalidSubscription, "Stripe subscription must have one item" unless items.is_a?(Array) && items.one?

      items.first
    end

    def price
      item.fetch("price")
    end

    def period_start
      item["current_period_start"] || stripe_subscription["current_period_start"]
    end

    def period_end
      item["current_period_end"] || stripe_subscription["current_period_end"]
    end

    def validate!(local)
      checks = [
        UserSubscription::STATUSES.include?(stripe_subscription["status"]),
        stripe_subscription["livemode"] == local.livemode,
        identifier(stripe_subscription["customer"]) == local.stripe_customer_id,
        identifier(price) == local.price_id,
        identifier(price["product"]) == UserSubscription::PRODUCT_ID,
        local.product_id == UserSubscription::PRODUCT_ID
      ]
      raise InvalidSubscription, "Stripe subscription does not match the local subscription" unless checks.all?
    end

    def identifier(value)
      value.is_a?(Hash) ? value["id"] : value
    end
  end
end
