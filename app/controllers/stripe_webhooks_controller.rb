# frozen_string_literal: true

class StripeWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    event = construct_event
    process_event(event)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  rescue Payments::FulfillCheckout::InvalidSession,
    Payments::FulfillSubscriptionInvoice::InvalidInvoice,
    Payments::LinkSubscriptionCheckout::InvalidSession,
    Payments::EndSubscription::InvalidSubscription,
    Payments::SyncSubscription::InvalidSubscription
    head :unprocessable_content
  end

  private

  def construct_event
    secret = Payments::Config.webhook_secret
    if secret.blank?
      raise Stripe::SignatureVerificationError.new("Webhook secret is not configured",
        request.headers["Stripe-Signature"], http_body: request.raw_post)
    end

    Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], secret)
  end

  def process_event(event)
    object_id = event.data.object.id
    return if event_processed?(event, object_id)

    remote_object = if %w[checkout.session.completed checkout.session.async_payment_succeeded].include?(event.type)
      Payments::StripeGateway.new.retrieve_checkout_session(object_id)
    elsif event.type == "invoice.paid"
      Payments::StripeGateway.new.retrieve_invoice(object_id)
    elsif event.type == "customer.subscription.updated"
      Payments::StripeGateway.new.retrieve_subscription(object_id)
    else
      event.data.object.to_hash.deep_stringify_keys
    end

    StripeEvent.transaction do
      return if event_processed?(event, object_id)

      case event.type
      when "checkout.session.completed"
        if remote_object["mode"] == "payment" && remote_object["payment_status"] == "paid"
          Payments::FulfillCheckout.call(session: remote_object)
        elsif remote_object["mode"] == "subscription"
          Payments::LinkSubscriptionCheckout.call(session: remote_object)
        end
      when "checkout.session.async_payment_succeeded"
        if remote_object["mode"] == "payment"
          Payments::FulfillCheckout.call(session: remote_object)
        elsif remote_object["mode"] == "subscription"
          Payments::LinkSubscriptionCheckout.call(session: remote_object)
        end
      when "invoice.paid"
        Payments::FulfillSubscriptionInvoice.call(invoice: remote_object)
      when "customer.subscription.deleted"
        Payments::EndSubscription.call(subscription: remote_object)
      when "customer.subscription.updated"
        Payments::SyncSubscription.call(subscription: remote_object)
      when "checkout.session.async_payment_failed"
        BookPurchase.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "failed", failure_reason: event.type, updated_at: Time.current)
        UserSubscription.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "incomplete_expired", failure_reason: event.type, updated_at: Time.current)
      when "checkout.session.expired"
        BookPurchase.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "expired", failure_reason: event.type, updated_at: Time.current)
        UserSubscription.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "incomplete_expired", failure_reason: event.type, updated_at: Time.current)
      end
      StripeEvent.create!(stripe_event_id: event.id, event_type: event.type,
        stripe_object_id: object_id, processed_at: Time.current)
    end
  end

  def event_processed?(event, object_id)
    return true if StripeEvent.exists?(stripe_event_id: event.id)
    return false if event.type == "customer.subscription.updated"

    StripeEvent.exists?(event_type: event.type, stripe_object_id: object_id)
  end
end
