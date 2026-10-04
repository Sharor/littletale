# frozen_string_literal: true

class BookParentApprovalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_book
  before_action :set_generation_request

  def show
  end

  def create
    control = current_user.parent_control
    unless control&.enabled? && control.authenticate_access_pin(params[:pin].to_s)
      flash.now[:alert] = I18n.t(control&.pin_locked? ? "parent.session.locked" : "parent.session.incorrect")
      return render :show, status: :unprocessable_content
    end

    result = ParentalGenerationApproval.call(@generation_request)
    if result == :stale
      redirect_to awaiting_approval_books_url, alert: I18n.t("parent.requests.stale")
    elsif result == :enqueue_failed
      redirect_to book_url(@book), alert: I18n.t("parent.requests.queue_failed")
    else
      redirect_to book_url(@book), notice: I18n.t("parent.requests.approved")
    end
  rescue TrialBookReservation::LimitReached, TrialBookReservation::TrialExpired, BookCredit::LimitReached
    @generation_request.update!(status: "pending", decided_at: nil)
    flash.now[:alert] = I18n.t("parent.requests.allowance_required")
    render :show, status: :unprocessable_content
  end

  private

  def set_book
    @book = current_user.books.active.find(params[:book_id])
  end

  def set_generation_request
    @generation_request = @book.parental_generation_requests.pending.order(:id).last
    redirect_to book_url(@book) unless @generation_request
  end
end
