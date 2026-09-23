# frozen_string_literal: true

class ReceivedGiftsController < ApplicationController
  skip_before_action :enforce_trial_access
  before_action :authenticate_user!

  def index
    @gifts = current_user.received_book_gifts.where.not(claimed_at: nil).order(claimed_at: :desc)
  end

  def show
    @gift = current_user.received_book_gifts.where.not(claimed_at: nil).find(params[:id])
  end
end
