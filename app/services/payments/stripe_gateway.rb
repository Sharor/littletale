# frozen_string_literal: true

module Payments
  class StripeGateway
    def retrieve_account
      normalize(Stripe::Account.retrieve)
    end

    def retrieve_product(product_id)
      normalize(Stripe::Product.retrieve({ id: product_id, expand: [ "default_price" ] }))
    end

    def create_checkout_session(params, idempotency_key:)
      normalize(Stripe::Checkout::Session.create(params, { idempotency_key: idempotency_key }))
    end

    def retrieve_checkout_session(session_id)
      normalize(Stripe::Checkout::Session.retrieve({
        id: session_id,
        expand: [ "line_items.data.price.product" ]
      }))
    end

    private

    def normalize(value)
      value.respond_to?(:to_hash) ? value.to_hash.deep_stringify_keys : value.deep_stringify_keys
    end
  end
end
