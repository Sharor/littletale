# frozen_string_literal: true

class Parent::GenerationRequestsController < Parent::BaseController
  before_action :load_generation_request

  def approve
    result = ParentalGenerationApproval.call(@generation_request, allow_declined: true)
    if result == :stale
      redirect_to parent_url, alert: I18n.t("parent.requests.stale")
    elsif result == :enqueue_failed
      redirect_to parent_url, alert: I18n.t("parent.requests.queue_failed")
    else
      redirect_to parent_url, notice: I18n.t("parent.requests.approved")
    end
  rescue TrialBookReservation::LimitReached, TrialBookReservation::TrialExpired, BookCredit::LimitReached,
      CharacterCredit::LimitReached
    @generation_request.update!(status: "pending", decided_at: nil)
    redirect_to parent_url, alert: I18n.t("parent.requests.allowance_required")
  end

  def decline
    @generation_request.with_lock do
      if @generation_request.pending?
        @generation_request.decline!
        @generation_request.generatable.soft_delete! if @generation_request.generatable.is_a?(Book)
      end
    end
    redirect_to parent_url, notice: I18n.t("parent.requests.declined")
  end

  private

  def load_generation_request
    @generation_request = parent_control.generation_requests.find(params[:id])
    if @generation_request.pending? && @generation_request.generatable.is_a?(Book) &&
        @generation_request.generatable.deleted_at.present?
      raise ActiveRecord::RecordNotFound
    end
  end
end
