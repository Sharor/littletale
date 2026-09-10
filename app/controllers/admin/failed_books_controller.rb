# frozen_string_literal: true

class Admin::FailedBooksController < ApplicationController
  skip_before_action :check_tutorial
  before_action :authenticate_user!
  before_action :require_admin

  def index
    @books = Book.failed.includes(:user, pages: :illustration).order(generation_failed_at: :desc)
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
