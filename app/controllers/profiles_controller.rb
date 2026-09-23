# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    if current_user.update(profile_params)
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
end
