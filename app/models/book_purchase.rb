# frozen_string_literal: true

class BookPurchase < ApplicationRecord
  PRODUCT_ID = "prod_VHc1FYY2QqVlJ0"
  CHARACTER_CREDITS_PER_PURCHASE = 5
  STATUSES = %w[pending paid failed expired].freeze

  belongs_to :user
  has_one :book_credit, dependent: :restrict_with_exception
  has_many :character_credits, dependent: :restrict_with_exception

  validates :status, inclusion: { in: STATUSES }
  validates :product_id, :idempotency_key, presence: true

  def fulfill!(checkout_session_id:, payment_intent_id:, stripe_customer_id:, price_id:, amount_total:, currency:)
    with_lock do
      return self if paid? && self.stripe_checkout_session_id == checkout_session_id

      update!(
        status: "paid",
        stripe_checkout_session_id: checkout_session_id,
        stripe_payment_intent_id: payment_intent_id,
        stripe_customer_id: stripe_customer_id,
        price_id: price_id,
        amount_total: amount_total,
        currency: currency,
        paid_at: Time.current,
        failure_reason: nil
      )
      create_book_credit!(user: user)
      CHARACTER_CREDITS_PER_PURCHASE.times do |index|
        character_credits.create!(user: user, ordinal: index + 1)
      end
      user.with_lock do
        user.update!(tier: user.trial? ? "basic" : user.tier, stripe_customer_id: stripe_customer_id)
      end
    end
    self
  end

  def paid?
    status == "paid"
  end
end
