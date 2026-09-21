# frozen_string_literal: true

module Payments
  class SubscriptionCheckout
    class ConfigurationError < StandardError; end
    class AlreadySubscribed < StandardError; end

    Result = Data.define(:subscription, :url)

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
      retire_expired_pending_subscriptions
      reusable = active_pending_subscription
      return Result.new(subscription: reusable, url: reusable.checkout_url) if reusable&.checkout_url.present?
      current = current_subscription
      raise AlreadySubscribed, "User already has a subscription" if current && current != reusable

      validate_account!
      product = gateway.retrieve_product(UserSubscription::PRODUCT_ID).deep_stringify_keys
      price = valid_default_price!(product)
      subscription = create_pending_subscription(product: product, price: price)
      session = gateway.create_checkout_session(
        session_parameters(subscription),
        idempotency_key: subscription.idempotency_key
      ).deep_stringify_keys
      subscription.update!(
        stripe_checkout_session_id: session.fetch("id"),
        checkout_url: session.fetch("url"),
        checkout_expires_at: Time.zone.at(session.fetch("expires_at"))
      )
      Result.new(subscription: subscription, url: subscription.checkout_url)
    rescue Stripe::InvalidRequestError, Stripe::AuthenticationError, Stripe::PermissionError => error
      if defined?(subscription) && subscription&.status == "pending"
        subscription.update!(status: "incomplete_expired", failure_reason: error.class.name)
      end
      raise
    end

    private

    attr_reader :user, :success_url, :cancel_url, :gateway

    def active_pending_subscription
      user.user_subscriptions.where(status: "pending")
        .where("checkout_expires_at IS NULL OR checkout_expires_at > ?", Time.current)
        .order(:id).last
    end

    def current_subscription
      user.user_subscriptions.current.order(:id).last
    end

    def retire_expired_pending_subscriptions
      user.user_subscriptions.where(status: "pending")
        .where(checkout_expires_at: ..Time.current)
        .update_all(status: "incomplete_expired", updated_at: Time.current)
    end

    def validate_account!
      expected = Config.account_id
      account = gateway.retrieve_account.deep_stringify_keys
      valid = expected.present? && account["id"] == expected
      raise ConfigurationError, "Stripe account does not match stripe.account" unless valid
    end

    def valid_default_price!(product)
      price = product["default_price"]
      recurring = price.is_a?(Hash) ? price["recurring"] : nil
      valid = product["id"] == UserSubscription::PRODUCT_ID && product["active"] && price.is_a?(Hash) &&
        price["active"] && price["type"] == "recurring" && price["id"].present? &&
        price["currency"].present? && price["unit_amount"].is_a?(Integer) && price["unit_amount"].positive? &&
        recurring.is_a?(Hash) && recurring["interval"] == "month" && recurring["interval_count"] == 1 &&
        product["livemode"] == Rails.env.production?
      raise ConfigurationError, "Stripe product requires an active monthly recurring default price" unless valid

      price
    end

    def create_pending_subscription(product:, price:)
      user.with_lock do
        existing = active_pending_subscription
        return existing if existing
        raise AlreadySubscribed, "User already has a subscription" if current_subscription

        user.user_subscriptions.where(status: "pending")
          .update_all(status: "incomplete_expired", updated_at: Time.current)
        user.user_subscriptions.create!(
          status: "pending",
          product_id: UserSubscription::PRODUCT_ID,
          price_id: price.fetch("id"),
          idempotency_key: SecureRandom.uuid,
          livemode: product.fetch("livemode")
        )
      end
    end

    def session_parameters(subscription)
      metadata = {
        user_subscription_id: subscription.id.to_s,
        user_id: user.id.to_s,
        product_id: UserSubscription::PRODUCT_ID
      }
      params = {
        mode: "subscription",
        line_items: [ { price: subscription.price_id, quantity: 1 } ],
        success_url: success_url,
        cancel_url: cancel_url,
        client_reference_id: subscription.id.to_s,
        metadata: metadata,
        subscription_data: { metadata: metadata }
      }
      if user.stripe_customer_id.present?
        params[:customer] = user.stripe_customer_id
      else
        params[:customer_email] = user.email
      end
      params
    end
  end
end
