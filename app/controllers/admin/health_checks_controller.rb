class Admin::HealthChecksController < ApplicationController
  skip_before_action :check_tutorial
  before_action -> { head :forbidden unless current_user&.admin? }

  def create
    results = [ HealthChecks::ObjectStorage.new.call, HealthChecks::Openai.new.call ]
    flash[:health_check_results] = results.map(&:to_h)
    redirect_to admin_root_path
  end
end
