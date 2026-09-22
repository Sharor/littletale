# frozen_string_literal: true

class Admin::CharacterImageAssessmentsController < ApplicationController
  FILTER_STATUSES = %w[needs_review rejected approved unavailable].freeze

  skip_before_action :check_tutorial
  before_action :require_admin
  before_action :set_assessment, except: :index

  def index
    @status = params[:status].presence_in(FILTER_STATUSES) || "needs_review"
    @user_id = params[:user_id].presence
    @assessments = filtered_assessments.includes(:user, :photo_attachment, requests: :generation_attempt)
      .distinct.order(created_at: :desc)
  end

  def show
    load_detail
  end

  def photo
    return head :not_found unless @assessment.photo.attached?

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
    safe_image = %w[image/png image/jpeg image/gif image/webp].include?(@assessment.photo.content_type)
    send_data @assessment.photo.download,
      type: safe_image ? @assessment.photo.content_type : "application/octet-stream",
      disposition: safe_image ? "inline" : "attachment",
      filename: @assessment.photo.filename.to_s
  end

  def retry_screening
    unless @assessment.status == "unavailable"
      redirect_to admin_character_image_assessment_path(@assessment),
        alert: I18n.t("admin.notices.screening_available")
      return
    end

    CharacterCredit.transaction do
      @assessment.requests.find_each do |request|
        CharacterFunding.reserve_for!(request) if request.current?
      end
    end
    queued = @assessment.retry_screening!
    redirect_to admin_character_image_assessment_path(@assessment),
      (queued ? { notice: I18n.t("admin.notices.screening_requested") } : { alert: I18n.t("admin.notices.screening_failed") })
  rescue CharacterCredit::LimitReached
    redirect_to admin_character_image_assessment_path(@assessment),
      alert: I18n.t("admin.notices.no_character_credits")
  end

  def retry_generation
    request = @assessment.requests.find(params[:request_id])
    queued = request.admin_retry_generation!(admin: current_user,
      expected_version: params[:attempt_version], confirm_unknown: params[:confirm_unknown] == "1")
    redirect_to admin_character_image_assessment_path(@assessment),
      notice: queued ? I18n.t("admin.notices.generation_queued") : I18n.t("admin.notices.generation_failed")
  end

  def release_character_credit
    request = @assessment.requests.find(params[:request_id])
    result = CharacterFunding.release_for_admin!(request, admin: current_user)
    message = case result
    when :released then I18n.t("admin.notices.character_credit_released")
    when :active then I18n.t("admin.notices.character_credit_active")
    else I18n.t("admin.notices.character_credit_unavailable")
    end
    redirect_to admin_character_image_assessment_path(@assessment),
      (result == :released ? { notice: message } : { alert: message })
  end

  def approve
    changed = @assessment.resolve!(
      outcome: "approved",
      source: "admin",
      reviewer: current_user,
      internal_reason: decision_params[:internal_reason].to_s.strip.presence
    )

    redirect_to admin_character_image_assessment_path(@assessment),
      notice: changed ? I18n.t("admin.notices.image_approved") : I18n.t("admin.notices.already_resolved")
  end

  def reject
    public_reason = decision_params[:public_reason].to_s.strip
    if public_reason.blank?
      load_detail
      flash.now[:alert] = I18n.t("admin.notices.reason_required")
      return render :show, status: :unprocessable_content
    end

    changed = @assessment.resolve!(
      outcome: "rejected",
      source: "admin",
      reviewer: current_user,
      internal_reason: decision_params[:internal_reason].to_s.strip.presence,
      public_reason: public_reason
    )

    redirect_to admin_character_image_assessment_path(@assessment),
      notice: changed ? I18n.t("admin.notices.image_rejected") : I18n.t("admin.notices.already_resolved")
  end

  private

  def filtered_assessments
    scope = CharacterImageAssessment.all
    scope = if @status == "rejected"
      scope.left_outer_joins(:requests).where(
        "character_image_assessments.status = :status OR character_image_requests.provider_rejected = :provider_rejected",
        status: "rejected",
        provider_rejected: true
      )
    else
      scope.where(status: @status)
    end
    @user_id ? scope.where(user_id: @user_id) : scope
  end

  def set_assessment
    @assessment = CharacterImageAssessment.find(params[:id])
  end

  def load_detail
    @requests = @assessment.requests.includes(:character, :generation_attempt).order(:created_at)
    @decisions = @assessment.decisions.includes(:request, :reviewer).order(:created_at)
  end

  def decision_params
    params.fetch(:decision, ActionController::Parameters.new).permit(:internal_reason, :public_reason)
  end

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
