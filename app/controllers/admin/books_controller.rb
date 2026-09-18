# frozen_string_literal: true

class Admin::BooksController < ApplicationController
  skip_before_action :check_tutorial
  before_action :require_admin

  def rerun_generation
    book = Book.find(params[:id])
    attempt = book.prepare_failed_regeneration!
    unless attempt
      redirect_back fallback_location: admin_failed_books_path,
        notice: "This book is no longer in a failed state."
      return
    end
    queued = book.enqueue_generation!(attempt: attempt)

    redirect_back fallback_location: admin_failed_books_path,
      notice: queued ? "Book generation restarted." : "Book generation could not be queued. Its trial slot was released."
  rescue TrialBookReservation::LimitReached
    redirect_back fallback_location: admin_failed_books_path,
      alert: "This user has no trial book slots available. Release another failed book slot first."
  rescue TrialBookReservation::TrialExpired
    redirect_back fallback_location: admin_failed_books_path,
      alert: "This user's trial has expired."
  end

  def release_trial_slot
    result = Book.find(params[:id]).release_trial_slot!(by: current_user)
    case result
    when :released
      redirect_to admin_failed_books_path, notice: "The trial book slot was released."
    when :retrying
      redirect_to admin_failed_books_path,
        alert: "This slot cannot be released while an illustration retry is in progress."
    else
      redirect_to admin_failed_books_path, notice: "This book does not hold a releasable trial slot."
    end
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
