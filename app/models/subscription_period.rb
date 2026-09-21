# frozen_string_literal: true

class SubscriptionPeriod < ApplicationRecord
  belongs_to :user_subscription
  has_many :book_credits, dependent: :restrict_with_exception
  has_many :character_credits, dependent: :restrict_with_exception

  validates :stripe_invoice_id, :price_id, :period_start, :period_end, presence: true
  validates :stripe_invoice_id, uniqueness: true
  validate :period_end_follows_start

  private

  def period_end_follows_start
    return if period_start.blank? || period_end.blank? || period_end > period_start

    errors.add(:period_end, "must follow the period start")
  end
end
