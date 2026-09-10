# frozen_string_literal: true

class PageIllustrationControlsController < ApplicationController
  skip_before_action :check_tutorial
  before_action :authenticate_user!

  def show
    page = Page.find(params[:id])
    return head :not_found unless current_user.admin? || page.book.user_id == current_user.id

    response.headers["Cache-Control"] = "private, no-store"
    render partial: "books/illustration_controls", locals: { page: page, admin: current_user }
  end
end
