# frozen_string_literal: true

class CharacterCreditReservation < ApplicationRecord
  belongs_to :user
  belongs_to :character_credit
  belongs_to :character_image_request, optional: true
  belongs_to :released_by, class_name: "User", optional: true

  scope :held, -> { where(status: "held") }

  validates :status, inclusion: { in: %w[held released consumed] }

  def release!(by: nil, reason:)
    user.with_lock do
      with_lock do
        return false unless status == "held"

        update!(status: "released", released_at: Time.current, released_by: by, release_reason: reason)
        status = character_credit.visible? || character_credit.expires_at > Time.current ? "available" : "expired"
        character_credit.update!(status: status)
      end
    end
    true
  end

  def consume!
    user.with_lock do
      with_lock do
        return false unless status == "held"

        update!(status: "consumed", consumed_at: Time.current)
        character_credit.update!(status: "consumed")
      end
    end
    true
  end
end
