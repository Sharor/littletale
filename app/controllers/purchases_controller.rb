# frozen_string_literal: true

class PurchasesController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial

  def create
    @gift_book = selected_gift_book
    if @gift_book
      session[:gift_purchase_book_id] = @gift_book.id
    else
      session.delete(:gift_purchase_book_id)
    end

    checkout = Payments::Checkout.call(
      user: current_user,
      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  rescue Payments::Checkout::ConfigurationError, Stripe::StripeError => error
    Rails.logger.error("Stripe Checkout could not start: #{error.class}")
    redirect_to checkout_failure_url, alert: I18n.t("notices.payment.unavailable")
  end

  def success
    session_id = params.require(:session_id)
    current_user.book_purchases.find_by!(stripe_checkout_session_id: session_id)
    stripe_session = Payments::StripeGateway.new.retrieve_checkout_session(session_id)
    Payments::FulfillCheckout.call(session: stripe_session)

    if (book = pending_gift_purchase_book)
      BookFunding.convert_trial_to_paid_for_gift!(book)
      session.delete(:gift_purchase_book_id)
      redirect_to new_book_book_gift_url(book), notice: I18n.t("book_gifts.trial_converted")
    else
      session.delete(:gift_purchase_book_id)
      redirect_to settings_url(checkout: "success"), notice: I18n.t("notices.payment.received")
    end
  rescue Payments::FulfillCheckout::InvalidSession
    redirect_to checkout_pending_url, notice: I18n.t("notices.payment.processing")
  end

  private

  def selected_gift_book
    return unless params[:gift_book_id].present?

    current_user.books.completed.find(params[:gift_book_id])
  end

  def pending_gift_purchase_book
    book_id = session[:gift_purchase_book_id]
    current_user.books.completed.find_by(id: book_id) if book_id.present?
  end

  def checkout_success_url
    settings_checkout_success_url(session_id: "CHECKOUT_SESSION_ID_PLACEHOLDER")
      .sub("CHECKOUT_SESSION_ID_PLACEHOLDER", "{CHECKOUT_SESSION_ID}")
  end

  def checkout_cancel_url
    return payment_required_book_book_gifts_url(@gift_book) if @gift_book

    settings_url(checkout: "canceled")
  end

  def checkout_failure_url
    return payment_required_book_book_gifts_url(@gift_book) if @gift_book

    settings_url
  end

  def checkout_pending_url
    book = pending_gift_purchase_book
    return payment_required_book_book_gifts_url(book, checkout: "pending") if book

    settings_url(checkout: "pending")
  end
end
