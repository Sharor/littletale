# frozen_string_literal: true

class PurchasesController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial

  def create
    checkout = Payments::Checkout.call(
      user: current_user,
      success_url: checkout_success_url,
      cancel_url: settings_url(checkout: "canceled")
    )
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  rescue Payments::Checkout::ConfigurationError, Stripe::StripeError => error
    Rails.logger.error("Stripe Checkout could not start: #{error.class}")
    redirect_to settings_url, alert: "Payment is temporarily unavailable. Please try again."
  end

  def success
    session_id = params.require(:session_id)
    current_user.book_purchases.find_by!(stripe_checkout_session_id: session_id)
    session = Payments::StripeGateway.new.retrieve_checkout_session(session_id)
    Payments::FulfillCheckout.call(session: session)
    redirect_to settings_url(checkout: "success"), notice: "Payment received. Your book credit is ready."
  rescue Payments::FulfillCheckout::InvalidSession
    redirect_to settings_url(checkout: "pending"),
      notice: "Your payment is still processing. Credits appear after Stripe confirms payment."
  end

  private

  def checkout_success_url
    settings_checkout_success_url(session_id: "CHECKOUT_SESSION_ID_PLACEHOLDER")
      .sub("CHECKOUT_SESSION_ID_PLACEHOLDER", "{CHECKOUT_SESSION_ID}")
  end
end
