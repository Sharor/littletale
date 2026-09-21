# frozen_string_literal: true

module Payments
  class FulfillSubscriptionInvoice
    class InvalidInvoice < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(invoice:)
      @invoice = invoice.respond_to?(:to_hash) ? invoice.to_hash.deep_stringify_keys : invoice.deep_stringify_keys
    end

    def call
      subscription = UserSubscription.find(metadata.fetch("user_subscription_id"))
      validate!(subscription)
      period = line.fetch("period")
      subscription.activate_period!(
        stripe_subscription_id: subscription_id,
        stripe_invoice_id: invoice.fetch("id"),
        stripe_customer_id: identifier(invoice["customer"]),
        price_id: price_id,
        period_start: Time.zone.at(period.fetch("start")),
        period_end: Time.zone.at(period.fetch("end"))
      )
      true
    rescue ActiveRecord::RecordNotFound, KeyError, TypeError, ArgumentError => error
      raise InvalidInvoice, error.message
    end

    private

    attr_reader :invoice

    def subscription_details
      invoice.dig("parent", "subscription_details") || invoice["subscription_details"] || {}
    end

    def metadata
      subscription_details["metadata"] || {}
    end

    def subscription_id
      identifier(subscription_details["subscription"] || invoice["subscription"])
    end

    def line
      lines = invoice.dig("lines", "data")
      raise InvalidInvoice, "Invoice must contain one subscription product line" unless lines.is_a?(Array)

      matching = lines.select { |candidate| line_product_id(candidate) == UserSubscription::PRODUCT_ID }
      raise InvalidInvoice, "Invoice must contain one subscription product line" unless matching.one?

      matching.first
    end

    def price_id
      pricing = line.dig("pricing", "price_details")
      identifier(pricing&.fetch("price", nil) || line.dig("price", "id") || line["price"])
    end

    def line_product_id(candidate)
      identifier(candidate.dig("pricing", "price_details", "product") || candidate.dig("price", "product"))
    end

    def validate!(subscription)
      period = line["period"]
      checks = [
        invoice["status"] == "paid",
        invoice["livemode"] == subscription.livemode,
        subscription.product_id == UserSubscription::PRODUCT_ID,
        metadata["user_subscription_id"] == subscription.id.to_s,
        metadata["user_id"] == subscription.user_id.to_s,
        metadata["product_id"] == UserSubscription::PRODUCT_ID,
        subscription_id.present?,
        subscription.stripe_subscription_id == subscription_id,
        identifier(invoice["customer"]) == subscription.stripe_customer_id,
        subscription.user.stripe_customer_id == subscription.stripe_customer_id,
        line["quantity"] == 1,
        price_id == subscription.price_id,
        period.is_a?(Hash),
        period&.fetch("start", nil).is_a?(Integer),
        period&.fetch("end", nil).is_a?(Integer),
        period&.fetch("end", 0).to_i > period&.fetch("start", 0).to_i
      ]
      raise InvalidInvoice, "Invoice does not match the subscription" unless checks.all?
    end

    def identifier(value)
      value.is_a?(Hash) ? value["id"] : value
    end
  end
end
