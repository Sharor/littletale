# frozen_string_literal: true

class CharacterCredit < ApplicationRecord
  class LimitReached < StandardError; end

  belongs_to :user
  belongs_to :book_purchase, optional: true
  belongs_to :subscription_period, optional: true
  has_many :character_credit_reservations, dependent: :restrict_with_exception

  scope :available, -> { where(status: "available") }
  scope :visible, -> { where(visible: true) }
  scope :monthly_allowance, -> { where(visible: false) }
  scope :spendable, -> {
    available.where("visible = ? OR expires_at > ?", true, Time.current).order(visible: :asc, id: :asc)
  }

  validates :status, inclusion: { in: %w[available reserved consumed expired] }
  validates :ordinal, uniqueness: { scope: :book_purchase_id }, if: :book_purchase_id?
  validates :ordinal, uniqueness: { scope: :subscription_period_id }, if: :subscription_period_id?
  validate :has_exactly_one_source

  def self.reserve_for!(request)
    user = request.user
    return if user.admin?

    user.with_lock do
      existing = CharacterCreditReservation.held.find_by(character_image_request: request)
      return existing if existing

      credit = user.character_credits.spendable.first
      raise LimitReached unless credit

      reservation = credit.character_credit_reservations.create!(user: user, character_image_request: request)
      credit.update!(status: "reserved")
      reservation
    end
  end

  private

  def has_exactly_one_source
    return if [ book_purchase_id.present?, subscription_period_id.present? ].one?

    errors.add(:base, "credit must belong to one funding source")
  end
end
