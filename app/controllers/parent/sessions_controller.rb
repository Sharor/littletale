# frozen_string_literal: true

class Parent::SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_parent_control
  skip_before_action :check_tutorial

  def new
    redirect_to profile_url, alert: I18n.t("parent.not_enabled") unless @parent_control&.enabled?
  end

  def create
    if @parent_control&.enabled? && @parent_control.authenticate_access_pin(params[:pin].to_s)
      session[:parent_access] = { user_id: current_user.id, authenticated_at: Time.current.to_i,
        pin_key: @parent_control.session_key }
      redirect_to parent_url
    else
      @locked = @parent_control&.pin_locked?
      flash.now[:alert] = I18n.t(@locked ? "parent.session.locked" : "parent.session.incorrect")
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session.delete(:parent_access)
    redirect_to profile_url, notice: I18n.t("parent.session.locked_again")
  end

  private

  def load_parent_control
    @parent_control = current_user.parent_control
  end
end
