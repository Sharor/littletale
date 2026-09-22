# frozen_string_literal: true

class Admin::PageIllustrationsController < ApplicationController
  skip_before_action :check_tutorial
  before_action :authenticate_user!
  before_action -> { head :forbidden unless current_user.admin? }

  def regenerate
    illustration = Illustration.joins(:page).find(params[:id])
    queued = illustration.page.book.enqueue_illustration_retry!(illustration, actor: current_user)
    redirect_back fallback_location: admin_failed_books_path,
      notice: queued ? I18n.t("admin.notices.illustration_queued") : I18n.t("notices.illustration.unavailable")
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
end
