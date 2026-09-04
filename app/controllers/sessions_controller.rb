# frozen_string_literal: true

# Takes care of callback after authentication
class SessionsController < ApplicationController
  # skip_before_action :authenticate_user!, only: %i[new]

  def new
    render :new
  end

  def create
    user_info = request.env["omniauth.auth"]
    Current.visitor.presence && Current.visitor.update!(user: current_user)
  end

  private
end
