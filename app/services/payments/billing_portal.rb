# frozen_string_literal: true

module Payments
  class BillingPortal
    class Unavailable < StandardError; end

    def self.call(user:, return_url:, gateway: StripeGateway.new)
      subscription = user.user_subscriptions.current.order(:id).last
      customer_id = user.stripe_customer_id
      valid = subscription.present? && customer_id.present? && subscription.stripe_customer_id == customer_id
      raise Unavailable, "Billing management is unavailable" unless valid

      session = gateway.create_billing_portal_session(customer: customer_id, return_url: return_url)
      session.fetch("url")
    end
  end
end
