# frozen_string_literal: true

class StripeWebhooksController < ActionController::Base
  skip_forgery_protection

  def create
    event = construct_event
    process_event(event)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  rescue Payments::FulfillCheckout::InvalidSession
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

    session = if %w[checkout.session.completed checkout.session.async_payment_succeeded].include?(event.type)
      Payments::StripeGateway.new.retrieve_checkout_session(object_id)
    end

    StripeEvent.transaction do
      return if event_processed?(event, object_id)

      case event.type
      when "checkout.session.completed"
        Payments::FulfillCheckout.call(session: session) if session["payment_status"] == "paid"
      when "checkout.session.async_payment_succeeded"
        Payments::FulfillCheckout.call(session: session)
      when "checkout.session.async_payment_failed"
        BookPurchase.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "failed", failure_reason: event.type, updated_at: Time.current)
      when "checkout.session.expired"
        BookPurchase.where(stripe_checkout_session_id: object_id, status: "pending")
          .update_all(status: "expired", failure_reason: event.type, updated_at: Time.current)
      end
      StripeEvent.create!(stripe_event_id: event.id, event_type: event.type,
        stripe_object_id: object_id, processed_at: Time.current)
    end
  end

  def event_processed?(event, object_id)
    StripeEvent.exists?(stripe_event_id: event.id) ||
      StripeEvent.exists?(event_type: event.type, stripe_object_id: object_id)
  end
end
