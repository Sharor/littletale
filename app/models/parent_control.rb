# frozen_string_literal: true

require "digest"

class ParentControl < ApplicationRecord
  MODES = %w[approval_required daily_limit].freeze
  MAX_PIN_ATTEMPTS = 5
  PIN_LOCK_DURATION = 15.minutes

  belongs_to :user
  has_many :generation_requests, class_name: "ParentalGenerationRequest", dependent: :restrict_with_exception

  has_secure_password :pin, validations: false
  generates_token_for :pin_reset, expires_in: 30.minutes do
    pin_digest
  end

  validates :mode, inclusion: { in: MODES }
  validates :daily_book_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validate :pin_is_valid

  def effective_mode
    return "approval_required" if mode == "daily_limit" && !subscription_features_available?

    mode
  end

  def subscription_features_available?
    user.admin? || active_subscription?
  end

  def active_subscription?
    user.user_subscriptions.where(status: "active").exists?
  end

  def local_date(time = Time.current)
    time.in_time_zone(time_zone).to_date
  end

  def local_day_range(time = Time.current)
    time.in_time_zone(time_zone).all_day
  end

  def authenticate_access_pin(candidate)
    with_lock do
      return false if pin_locked?

      if authenticate_pin(candidate)
        update_columns(failed_pin_attempts: 0, locked_until: nil)
        true
      else
        attempts = failed_pin_attempts + 1
        update_columns(
          failed_pin_attempts: attempts,
          locked_until: attempts >= MAX_PIN_ATTEMPTS ? PIN_LOCK_DURATION.from_now : nil
        )
        false
      end
    end
  end

  def pin_locked?
    locked_until.present? && locked_until.future?
  end

  def session_key
    Digest::SHA256.hexdigest(pin_digest)
  end

  private

  def pin_is_valid
    return if pin_digest.present? && pin.blank?

    errors.add(:pin, "must be 4 to 8 digits") unless pin.to_s.match?(/\A\d{4,8}\z/)
    errors.add(:pin_confirmation, "doesn't match PIN") unless pin == pin_confirmation
  end
end
