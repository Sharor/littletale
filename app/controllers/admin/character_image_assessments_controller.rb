# frozen_string_literal: true

class Admin::CharacterImageAssessmentsController < ApplicationController
  FILTER_STATUSES = %w[needs_review rejected approved].freeze

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

  def approve
    changed = @assessment.resolve!(
      outcome: "approved",
      source: "admin",
      reviewer: current_user,
      internal_reason: decision_params[:internal_reason].to_s.strip.presence
    )

    redirect_to admin_character_image_assessment_path(@assessment),
      notice: changed ? "Character image approved." : "This assessment has already been resolved."
  end

  def reject
    public_reason = decision_params[:public_reason].to_s.strip
    if public_reason.blank?
      load_detail
      flash.now[:alert] = "Enter a public reason before rejecting this image."
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
      notice: changed ? "Character image rejected." : "This assessment has already been resolved."
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
