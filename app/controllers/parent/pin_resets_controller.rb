# frozen_string_literal: true

class Parent::PinResetsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_parent_control
  skip_before_action :check_tutorial

  def new
  end

  def create
    ParentControlMailer.with(control: @parent_control).pin_reset.deliver_later
    redirect_to profile_url, notice: I18n.t("parent.pin_reset.sent")
  end

  def edit
    @token = params[:token]
    @valid_token = valid_token_control.present?
  end

  def update
    @token = params[:token]
    token_control = valid_token_control
    unless token_control
      @valid_token = false
      return render :edit, status: :unprocessable_content
    end

    @parent_control = token_control
    if @parent_control.update(pin_params.merge(failed_pin_attempts: 0, locked_until: nil))
      session[:parent_access] = { user_id: current_user.id, authenticated_at: Time.current.to_i,
        pin_key: @parent_control.session_key }
      redirect_to parent_url, notice: I18n.t("parent.pin_reset.updated")
    else
      @valid_token = true
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_parent_control
    @parent_control = current_user.parent_control
    redirect_to profile_url, alert: I18n.t("parent.not_enabled") unless @parent_control
  end

  def valid_token_control
    control = ParentControl.find_by_token_for(:pin_reset, params[:token].to_s)
    control if control&.user_id == current_user.id
  end

  def pin_params
    params.require(:parent_control).permit(:pin, :pin_confirmation)
  end
end
