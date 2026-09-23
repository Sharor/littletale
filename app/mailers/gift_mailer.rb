# frozen_string_literal: true

class GiftMailer < ApplicationMailer
  default from: ENV.fetch("RESEND_FROM_EMAIL", "LittleTale <onboarding@resend.dev>")

  def invitation
    @gift = params.fetch(:gift)
    @token = params.fetch(:token)
    @invitation_url = gift_invitation_url(@token)

    I18n.with_locale(@gift.language) do
      mail(
        to: @gift.recipient_email,
        subject: I18n.t("book_gifts.mailer.subject", sender: @gift.sender_callname),
        options: { idempotency_key: params[:delivery_attempt_id] }
      )
    end
  end
end
