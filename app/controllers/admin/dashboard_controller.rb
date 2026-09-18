class Admin::DashboardController < ApplicationController
  skip_before_action :check_tutorial
  before_action -> { head :forbidden unless current_user&.admin? }

  def index
    @reviews = CharacterImageAssessment.where(status: "needs_review").count
    @failed_books = Book.failed.count
    @users = User.includes(:trial_book_reservations, :book_credits, :character_credits).order(:email).reject(&:admin?)
  end
end
