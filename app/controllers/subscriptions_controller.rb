# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial

  def create
    checkout = Payments::SubscriptionCheckout.call(
      user: current_user,
      success_url: settings_url(subscription: "success"),
      cancel_url: settings_url(subscription: "canceled")
    )
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  rescue Payments::SubscriptionCheckout::AlreadySubscribed
    redirect_to settings_url, notice: "Your subscription is already active."
  rescue Payments::SubscriptionCheckout::ConfigurationError, Stripe::StripeError => error
    Rails.logger.error("Stripe subscription Checkout could not start: #{error.class}")
    redirect_to settings_url, alert: "Subscriptions are temporarily unavailable. Please try again."
  end
end
