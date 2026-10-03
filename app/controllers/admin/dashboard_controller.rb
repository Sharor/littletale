class Admin::DashboardController < ApplicationController
  skip_before_action :check_tutorial
  before_action -> { head :forbidden unless current_user&.admin? }

  def index
    @reviews = CharacterImageAssessment.where(status: "needs_review").count
    @failed_books = Book.failed.count
    @users = User.includes(:trial_book_reservations, :book_credits, :character_credits).order(:email).reject(&:admin?)
    @generation_provider_setting = GenerationProviderSetting.current
    @generation_provider_window = @generation_provider_setting.eligible_openai_window
    @generation_provider_failures = @generation_provider_window.count do |request|
      request.outcome == "availability_failure"
    end
    @generation_provider_credentials = {
      "openai" => ENV["OPENAI_ACCESS_TOKEN"].present?,
      "gemini" => ENV["GEMINI_API_KEY"].present?
    }
    health_check_results = flash[:health_check_results]
    flash.delete(:health_check_results)
    @health_check_results = Array(health_check_results).index_by do |entry|
      entry["name"] || entry[:name]
    end
  end
end
