# frozen_string_literal: true

class ReceivedGiftImagesController < ApplicationController
  skip_before_action :enforce_trial_access
  before_action :authenticate_user!

  def show
    gift = current_user.received_book_gifts.where.not(claimed_at: nil).find(params[:received_gift_id])
    page = gift.gift_pages.find(params[:id])
    return head :not_found unless page.image.attached?

    send_data page.image.download,
      filename: page.image.filename.to_s,
      type: page.image.content_type,
      disposition: "inline"
  end
end
