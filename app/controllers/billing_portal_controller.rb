# frozen_string_literal: true

class BillingPortalController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial

  def create
    url = Payments::BillingPortal.call(user: current_user, return_url: settings_url)
    redirect_to url, allow_other_host: true, status: :see_other
  rescue Payments::BillingPortal::Unavailable, Stripe::StripeError => error
    Rails.logger.error("Stripe billing portal could not start: #{error.class}")
    redirect_to settings_url, alert: I18n.t("notices.subscription.management_unavailable")
  end
end
