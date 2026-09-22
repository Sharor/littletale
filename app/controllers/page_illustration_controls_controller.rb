# frozen_string_literal: true

class PageIllustrationControlsController < ApplicationController
  skip_before_action :check_tutorial
  before_action :authenticate_user!

  def show
    page = Page.find(params[:id])
    return head :not_found unless current_user.admin? || page.book.user_id == current_user.id

    response.headers["Cache-Control"] = "private, no-store"
    render partial: "books/illustration_controls", locals: { page: page, actor: current_user }
  end

  def regenerate
    page = Page.find(params[:id])
    return head :not_found unless page.book.user_id == current_user.id

    queued = page.illustration && page.book.enqueue_illustration_retry!(page.illustration, actor: current_user)
    redirect_back fallback_location: book_path(page.book),
      notice: queued ? I18n.t("notices.illustration.queued") : I18n.t("notices.illustration.unavailable")
  rescue TrialBookReservation::LimitReached
    redirect_back fallback_location: book_path(page.book),
      alert: I18n.t("notices.illustration.trial_slots")
  rescue TrialBookReservation::TrialExpired
    redirect_to settings_path, alert: I18n.t("notices.trial_ended")
  rescue BookCredit::LimitReached
    redirect_to settings_path(payment_required: "book"),
      alert: I18n.t("notices.illustration.credit_required")
  end
end
