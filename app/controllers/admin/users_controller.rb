# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  skip_before_action :check_tutorial
  before_action :require_admin
  before_action :set_user, only: %i[show unlock_parent_pin]

  def index
    @query = params[:query].to_s.strip
    scope = User.includes(:trial_book_reservations, :book_credits, :character_credits).order(:email)
    if @query.present?
      pattern = "%#{User.sanitize_sql_like(@query.downcase)}%"
      scope = scope.where("LOWER(email) LIKE ?", pattern)
    end
    @users = scope
  end

  def show
    @current_books = @user.books.active.order(updated_at: :desc)
    @deleted_books = @user.books.deleted.order(deleted_at: :desc)
  end

  def unlock_parent_pin
    @user.parent_control&.update!(failed_pin_attempts: 0, locked_until: nil)
    redirect_to admin_user_url(@user), notice: I18n.t("admin.users.parent_pin_unlocked"), status: :see_other
  end

  private

  def require_admin
    head :forbidden unless current_user&.admin?
  end

  def set_user
    @user = User.find(params[:id])
  end
end
