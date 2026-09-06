# frozen_string_literal: true

class Admin::BooksController < ApplicationController
  skip_before_action :check_tutorial
  before_action :require_admin

  def rerun_generation
    book = Book.find(params[:id])
    attempt = book.prepare_for_regeneration!
    GenerateBookJob.perform_later(book.id, attempt)

    redirect_back fallback_location: admin_failed_books_path, notice: "Book generation restarted."
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end
end
