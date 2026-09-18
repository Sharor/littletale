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
      notice: queued ? "Illustration retry queued." : "This illustration cannot be retried or already has a retry in progress."
  rescue TrialBookReservation::LimitReached
    redirect_back fallback_location: book_path(page.book),
      alert: "All three trial book slots are currently reserved."
  rescue TrialBookReservation::TrialExpired
    redirect_to settings_path, alert: "Your trial has ended. Subscribe to continue."
  end
end
