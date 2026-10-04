# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @parent_control = current_user.parent_control
  end

  def update
    @parent_control = current_user.parent_control
    updated = false
    User.transaction do
      current_user.assign_attributes(profile_params)
      if parent_restriction_valid? && current_user.save
        @parent_control&.save!
        updated = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if updated
      notice = I18n.with_locale(current_user.language) { I18n.t("profile.updated") }
      redirect_to params[:onboarding].present? ? (pending_gift_url || books_url) : profile_url,
        notice: notice
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def profile_params
    params.require(:user).permit(:language, :reader_age)
  end

  def parent_restriction_valid?
    user_params = params.require(:user)
    requested = if user_params.key?(:parent_restricted_mode)
      ActiveModel::Type::Boolean.new.cast(user_params[:parent_restricted_mode])
    else
      @parent_control&.enabled? || false
    end
    return true if requested == (@parent_control&.enabled? || false)

    if @parent_control.nil?
      @parent_control = current_user.build_parent_control(
        enabled: requested,
        pin: user_params[:parent_pin],
        pin_confirmation: user_params[:parent_pin_confirmation]
      )
      return true if @parent_control.valid?

      copy_parent_control_errors
      return false
    end

    unless @parent_control.authenticate_access_pin(user_params[:current_parent_pin].to_s)
      current_user.errors.add(:base, I18n.t("profile.parent_control.pin_incorrect"))
      return false
    end

    @parent_control.enabled = requested
    true
  end

  def copy_parent_control_errors
    @parent_control.errors.full_messages.each { |message| current_user.errors.add(:base, message) }
  end
end
