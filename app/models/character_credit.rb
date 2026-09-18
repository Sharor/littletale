# frozen_string_literal: true

class CharacterCredit < ApplicationRecord
  class LimitReached < StandardError; end

  belongs_to :user
  belongs_to :book_purchase
  has_many :character_credit_reservations, dependent: :restrict_with_exception

  scope :available, -> { where(status: "available") }

  validates :status, inclusion: { in: %w[available reserved consumed] }
  validates :ordinal, uniqueness: { scope: :book_purchase_id }

  def self.reserve_for!(request)
    user = request.user
    return if user.admin?

    user.with_lock do
      existing = CharacterCreditReservation.held.find_by(character_image_request: request)
      return existing if existing

      credit = user.character_credits.available.order(:id).first
      raise LimitReached unless credit

      reservation = credit.character_credit_reservations.create!(user: user, character_image_request: request)
      credit.update!(status: "reserved")
      reservation
    end
  end
end
