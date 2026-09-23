# frozen_string_literal: true

class GiftInvitationsController < ApplicationController
  skip_before_action :enforce_trial_access
  before_action :set_gift
  before_action :authenticate_user!, only: %i[claim switch_account]

  def show
    store_location_for(:user, gift_invitation_path(params[:token])) unless user_signed_in?
  end

  def switch_account
    sign_out(:user)
    redirect_to gift_invitation_url(params[:token])
  end

  def claim
    @gift.claim!(current_user)
    session.delete(:pending_gift_token)
    redirect_to received_gift_url(@gift), notice: I18n.t("book_gifts.claimed")
  rescue BookGift::RecipientMismatch, BookGift::UnverifiedRecipient
    render :show, status: :forbidden
  end

  private

  def set_gift
    @gift = BookGift.find_by_invitation_token(params[:token])
    head :not_found unless @gift
  end
end
