# frozen_string_literal: true

module Payments
  class Checkout
    class ConfigurationError < StandardError; end

    Result = Data.define(:purchase, :url)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, success_url:, cancel_url:, gateway: StripeGateway.new)
      @user = user
      @success_url = success_url
      @cancel_url = cancel_url
      @gateway = gateway
    end

    def call
      reusable = active_pending_purchase
      return Result.new(purchase: reusable, url: reusable.checkout_url) if reusable&.checkout_url.present?

      validate_account!
      product = gateway.retrieve_product(BookPurchase::PRODUCT_ID).deep_stringify_keys
      price = valid_default_price!(product)
      purchase = reusable || create_pending_purchase(product: product, price: price)
      session = gateway.create_checkout_session(session_parameters(purchase),
        idempotency_key: purchase.idempotency_key).deep_stringify_keys
      purchase.update!(
        stripe_checkout_session_id: session.fetch("id"),
        checkout_url: session.fetch("url"),
        checkout_expires_at: Time.zone.at(session.fetch("expires_at"))
      )
      Result.new(purchase: purchase, url: purchase.checkout_url)
    rescue Stripe::InvalidRequestError, Stripe::AuthenticationError, Stripe::PermissionError => error
      if defined?(purchase) && purchase&.status == "pending"
        purchase.update!(status: "failed", failure_reason: error.class.name)
      end
      raise
    end

    private

    attr_reader :user, :success_url, :cancel_url, :gateway

    def active_pending_purchase
      user.book_purchases.where(status: "pending").where("checkout_expires_at IS NULL OR checkout_expires_at > ?", Time.current)
        .order(:id).last
    end

    def validate_account!
      expected = Config.account_id
      account = gateway.retrieve_account.deep_stringify_keys
      valid = expected.present? && account["id"] == expected
      raise ConfigurationError, "Stripe account does not match stripe.account" unless valid
    end

    def create_pending_purchase(product:, price:)
      user.with_lock do
        existing = active_pending_purchase
        return existing if existing

        user.book_purchases.where(status: "pending").update_all(status: "expired", updated_at: Time.current)
        user.book_purchases.create!(
          status: "pending",
          product_id: BookPurchase::PRODUCT_ID,
          price_id: price.fetch("id"),
          idempotency_key: SecureRandom.uuid,
          amount_total: price.fetch("unit_amount"),
          currency: price.fetch("currency"),
          livemode: product.fetch("livemode")
        )
      end
    end

    def valid_default_price!(product)
      price = product["default_price"]
      valid = product["id"] == BookPurchase::PRODUCT_ID && product["active"] && price.is_a?(Hash) &&
        price["active"] && price["type"] == "one_time" && price["id"].present? &&
        price["currency"].present? && price["unit_amount"].is_a?(Integer) && price["unit_amount"].positive? &&
        product["livemode"] == Rails.env.production?
      raise ConfigurationError, "Stripe product requires an active one-time default price" unless valid

      price
    end

    def session_parameters(purchase)
      params = {
        mode: "payment",
        line_items: [ { price: purchase.price_id, quantity: 1 } ],
        success_url: success_url,
        cancel_url: cancel_url,
        client_reference_id: purchase.id.to_s,
        metadata: {
          purchase_id: purchase.id.to_s,
          user_id: user.id.to_s,
          product_id: BookPurchase::PRODUCT_ID
        }
      }
      if user.stripe_customer_id.present?
        params[:customer] = user.stripe_customer_id
      else
        params[:customer_creation] = "always"
        params[:customer_email] = user.email
      end
      params
    end
  end
end
