# frozen_string_literal: true

class BookGiftsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_giftable_book, only: %i[new create]

  def new
    @book_gift = BookGift.new(
      sender_callname: current_user.name.presence || current_user.email.to_s.split("@").first,
      message: default_message,
      language: current_user.language.presence_in(User::SUPPORTED_LANGUAGES.keys) || I18n.default_locale.to_s,
      issuance_key: SecureRandom.uuid
    )
  end

  def create
    @book_gift = BookGift.issue!(source_book: @book, sender: current_user, attributes: book_gift_params)
    token = @book_gift.invitation_token

    if params[:delivery] == "email" && @book_gift.issued_now?
      attempt_id = SecureRandom.uuid
      @book_gift.update!(delivery_status: "queued", email_queued_at: Time.current,
        delivery_attempt_id: attempt_id)
      DeliverGiftEmailJob.perform_later(@book_gift.id, attempt_id)
    end

    redirect_to gift_invitation_url(token), notice: I18n.t("book_gifts.created")
  rescue ActiveRecord::RecordInvalid => error
    @book_gift = error.record
    render :new, status: :unprocessable_content
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    @book_gift&.update!(delivery_status: "failed", delivery_error: error.message)
    redirect_to gift_invitation_url(token), alert: I18n.t("book_gifts.delivery_failed")
  end

  def retry_delivery
    gift = current_user.sent_book_gifts.find(params[:id])
    return head :unprocessable_content unless gift.delivery_status == "failed"

    token = gift.recovered_invitation_token
    attempt_id = gift.delivery_attempt_id.presence || SecureRandom.uuid
    gift.update!(delivery_status: "queued", delivery_error: nil, email_queued_at: Time.current,
      delivery_attempt_id: attempt_id)
    DeliverGiftEmailJob.perform_later(gift.id, attempt_id)
    redirect_to gift_invitation_url(token), notice: I18n.t("book_gifts.delivery_retried")
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    gift&.update!(delivery_status: "failed", delivery_error: error.message)
    redirect_to gift_invitation_url(token), alert: I18n.t("book_gifts.delivery_failed")
  end

  private

  def set_giftable_book
    @book = current_user.books.find(params[:book_id])
    head :not_found unless @book.giftable?
  end

  def book_gift_params
    params.require(:book_gift).permit(:recipient_name, :recipient_email, :sender_callname, :message, :language, :issuance_key)
  end

  def default_message
    locale = current_user.language.presence_in(User::SUPPORTED_LANGUAGES.keys) || I18n.default_locale
    I18n.t("book_gifts.default_message", locale: locale)
  end
end
