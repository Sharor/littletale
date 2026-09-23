# frozen_string_literal: true

class DeliverGiftEmailJob < ApplicationJob
  self.log_arguments = false
  queue_as :default

  def perform(gift_id, attempt_id)
    gift = BookGift.find(gift_id)
    gift.with_lock do
      return unless gift.delivery_status == "queued" && gift.delivery_attempt_id == attempt_id

      GiftMailer.with(gift: gift, token: gift.recovered_invitation_token,
        delivery_attempt_id: attempt_id).invitation.deliver_now!
      gift.update!(delivery_status: "sent", delivered_at: Time.current, delivery_error: nil)
    end
  rescue StandardError => error
    mark_failed(gift, attempt_id, error)
    raise
  end

  private

  def mark_failed(gift, attempt_id, error)
    return unless gift

    gift.with_lock do
      return unless gift.delivery_attempt_id == attempt_id

      gift.update_columns(
        delivery_status: "failed",
        delivery_error: error.message.to_s.first(1_000),
        updated_at: Time.current
      )
    end
  end
end
