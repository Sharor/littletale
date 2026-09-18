# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_tutorial

  def show
    @purchases = current_user.book_purchases.order(created_at: :desc).limit(20)
  end
end
