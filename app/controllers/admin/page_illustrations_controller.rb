# frozen_string_literal: true

class Admin::PageIllustrationsController < ApplicationController
  skip_before_action :check_tutorial
  before_action :authenticate_user!
  before_action -> { head :forbidden unless current_user.admin? }

  def regenerate
    illustration = Illustration.joins(:page).find(params[:id])
    queued = PageIllustrationGeneration.enqueue!(illustration, admin: current_user)
    redirect_back fallback_location: admin_failed_books_path,
      notice: queued ? "Illustration retry queued with a revised prompt." : "This illustration cannot be retried or already has a retry in progress."
  end
end
