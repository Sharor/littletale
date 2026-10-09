# frozen_string_literal: true

class Parent::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_enabled_parent_control!
  before_action :require_parent_authorization!
  skip_before_action :check_tutorial

  private

  def require_enabled_parent_control!
    redirect_to profile_url, alert: I18n.t("parent.not_enabled") unless parent_control&.enabled?
  end

  def require_parent_authorization!
    return if parent_authorized?

    redirect_to new_parent_session_url
  end

  def load_dashboard
    @parent_control = parent_control.reload
    remove_orphaned_generation_requests!
    @pending_requests = @parent_control.generation_requests.pending.includes(:generatable).order(:created_at).reject do |request|
      request.generatable.is_a?(Book) && request.generatable.deleted_at.present?
    end
    @recent_requests = @parent_control.generation_requests.where.not(status: "pending")
      .includes(:generatable).order(updated_at: :desc).limit(10)
    @successful_books_today = @parent_control.generation_requests.where(kind: "book", status: "completed",
      completed_at: @parent_control.local_day_range).count
    active_book_ids = current_user.books.active.where(generation_status: %i[pending in_progress]).select(:id)
    @in_progress_books = @parent_control.generation_requests.where(kind: "book", status: "approved",
      generatable_type: "Book", generatable_id: active_book_ids).count
    if @parent_control.effective_mode == "daily_limit"
      @remaining_book_slots = [ @parent_control.daily_book_limit - @successful_books_today - @in_progress_books, 0 ].max
    end
  end

  def remove_orphaned_generation_requests!
    @parent_control.generation_requests.where(generatable_type: "Book")
      .where.not(generatable_id: Book.select(:id)).delete_all
    @parent_control.generation_requests.where(generatable_type: "Character")
      .where.not(generatable_id: Character.select(:id)).delete_all
  end
end
