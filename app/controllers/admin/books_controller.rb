# frozen_string_literal: true

class Admin::BooksController < ApplicationController
  skip_before_action :check_tutorial
  before_action :require_admin

  def rerun_generation
    book = Book.find(params[:id])
    attempt = book.prepare_failed_regeneration!
    unless attempt
      redirect_back fallback_location: admin_failed_books_path,
        notice: I18n.t("admin.notices.book_not_failed")
      return
    end
    queued = book.enqueue_generation!(attempt: attempt, reservation: book.prepared_funding_reservation,
      release_on_failure: book.prepared_funding_newly_acquired)

    redirect_back fallback_location: admin_failed_books_path,
      notice: queued ? I18n.t("admin.notices.book_restarted") : book.generation_failure["message"]
  rescue TrialBookReservation::LimitReached
    redirect_back fallback_location: admin_failed_books_path,
      alert: I18n.t("admin.notices.no_trial_slots")
  rescue TrialBookReservation::TrialExpired
    redirect_back fallback_location: admin_failed_books_path,
      alert: I18n.t("admin.notices.user_trial_expired")
  rescue BookCredit::LimitReached
    redirect_back fallback_location: admin_failed_books_path,
      alert: I18n.t("admin.notices.no_book_credits")
  end

  def release_trial_slot
    result = Book.find(params[:id]).release_trial_slot!(by: current_user)
    case result
    when :released
      redirect_to admin_failed_books_path, notice: I18n.t("admin.notices.generation_credit_released")
    when :retrying
      redirect_to admin_failed_books_path,
        alert: I18n.t("admin.notices.slot_retrying")
    else
      redirect_to admin_failed_books_path, notice: I18n.t("admin.notices.no_releasable_credit")
    end
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
