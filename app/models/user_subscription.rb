# frozen_string_literal: true

class UserSubscription < ApplicationRecord
  PRODUCT_ID = "prod_VInAXXEHxVHfXh"
  BOOKS_PER_PERIOD = 50
  CHARACTERS_PER_PERIOD = 150
  SAVED_BOOK_CAP = 10
  SAVED_CHARACTER_CAP = 20
  CURRENT_STATUSES = %w[pending active past_due unpaid].freeze
  STATUSES = (CURRENT_STATUSES + %w[incomplete incomplete_expired paused canceled]).freeze

  belongs_to :user
  has_many :subscription_periods, dependent: :restrict_with_exception

  validates :status, inclusion: { in: STATUSES }
  validates :product_id, :idempotency_key, presence: true

  scope :current, -> {
    where(status: CURRENT_STATUSES - [ "pending" ]).or(
      where(status: "pending").where("checkout_expires_at IS NULL OR checkout_expires_at > ?", Time.current)
    )
  }

  def activate_period!(stripe_subscription_id:, stripe_invoice_id:, stripe_customer_id:, price_id:,
    period_start:, period_end:)
    user.with_lock do
      with_lock do
        return self if status == "canceled"
        return self if subscription_periods.exists?(stripe_invoice_id: stripe_invoice_id)
        latest_granted_period_end = subscription_periods.maximum(:period_end)
        return self if latest_granted_period_end.present? && period_end <= latest_granted_period_end

        save_unused_allowance!
        period = subscription_periods.create!(
          stripe_invoice_id: stripe_invoice_id,
          price_id: price_id,
          period_start: period_start,
          period_end: period_end
        )
        BOOKS_PER_PERIOD.times do
          user.book_credits.create!(subscription_period: period, visible: false, expires_at: period_end)
        end
        CHARACTERS_PER_PERIOD.times do |index|
          user.character_credits.create!(
            subscription_period: period,
            ordinal: index + 1,
            visible: false,
            expires_at: period_end
          )
        end
        update!(
          status: "active",
          stripe_subscription_id: stripe_subscription_id,
          stripe_customer_id: stripe_customer_id,
          price_id: price_id,
          current_period_start: period_start,
          current_period_end: period_end,
          ended_at: nil,
          failure_reason: nil
        )
        user.update!(tier: user.trial? ? "basic" : user.tier, stripe_customer_id: stripe_customer_id)
      end
    end
    self
  end

  def end!(ended_at: Time.current)
    user.with_lock do
      with_lock do
        save_unused_allowance!
        expire_held_allowance!
        update!(status: "canceled", ended_at: ended_at, cancel_at_period_end: false)
      end
    end
    self
  end

  private

  def save_unused_allowance!
    save_credits!(user.book_credits, SAVED_BOOK_CAP)
    save_credits!(user.character_credits, SAVED_CHARACTER_CAP)
  end

  def expire_held_allowance!
    [ user.book_credits, user.character_credits ].each do |credits|
      credits.monthly_allowance.where(status: "reserved")
        .joins(:subscription_period)
        .where(subscription_periods: { user_subscription_id: id })
        .update_all(expires_at: Time.current, updated_at: Time.current)
    end
  end

  def save_credits!(credits, cap)
    visible_unspent = credits.where(visible: true, status: %w[available reserved]).count
    allowance = credits.monthly_allowance.available
      .joins(:subscription_period)
      .where(subscription_periods: { user_subscription_id: id })
      .order(:id)
    allowance.limit([ cap - visible_unspent, 0 ].max).update_all(visible: true, expires_at: nil, updated_at: Time.current)
    allowance.update_all(status: "expired", updated_at: Time.current)
  end
end
