# frozen_string_literal: true

class User < ApplicationRecord
  SUPPORTED_LANGUAGES = { "en" => "English", "da" => "Dansk" }.freeze
  GENERATION_LANGUAGE_NAMES = { "en" => "English", "da" => "Danish" }.freeze

  has_many :books, dependent: :nullify
  has_many :visits, class_name: "Visitor"
  has_many :events, through: :visits
  has_many :action_logs
  has_many :characters
  has_many :character_image_assessments
  has_many :character_image_requests
  has_many :character_image_decisions
  has_many :trial_book_reservations, dependent: :destroy
  has_many :book_purchases, dependent: :restrict_with_exception
  has_many :book_credits, dependent: :restrict_with_exception
  has_many :character_credits, dependent: :restrict_with_exception
  has_many :book_credit_reservations, dependent: :restrict_with_exception
  has_many :character_credit_reservations, dependent: :restrict_with_exception
  has_many :user_subscriptions, dependent: :restrict_with_exception
  has_one :tutorial

  validates :language, inclusion: { in: SUPPORTED_LANGUAGES.keys }, allow_nil: true
  validates :reader_age, numericality: { only_integer: true, in: 0..120 }, allow_nil: true

  TRIAL_BOOK_LIMIT = 3

  ADMINS = %w[ davchristensen90@gmail.com ]
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :trackable, :omniauthable, omniauth_providers: [ :google_oauth2 ]

  def admin?
    return true if ADMINS.include?(email)

    super
  end

  def self.from_omniauth(access_token)
    data = access_token.info
    user = User.where(email: data["email"]).first

    # Create user when they don't exist
    user ||= User.create(
      name: data["name"],
      email: data["email"],
      tier: "free",
      encrypted_password: Devise.friendly_token[0, 20]
    )
    user
  end

  def time_on_site
    Visitor.total_time_on_site_for_visitor(visits)
  end

  def average_time_on_site
    Visitor.average_time_on_site_for_visitor(visits)
  end

  def trial?
    !admin? && !paid?
  end

  def paid?
    tier.present? && tier != "free"
  end

  def access_type
    return "admin" if admin?

    paid? ? "paid" : "trial"
  end

  def trial_status
    return access_type unless trial?
    return "expired" if trial_expired?
    return "active" if trial_started_at.present?

    "not_started"
  end

  def trial_expired?
    trial? && trial_expires_at.present? && trial_expires_at <= Time.current
  end

  def trial_books_remaining
    return unless trial?

    [ TRIAL_BOOK_LIMIT - trial_book_reservations.held.count, 0 ].max
  end

  def start_trial!
    return unless trial?

    with_lock do
      return if trial_started_at.present?

      started_at = Time.current
      update!(trial_started_at: started_at, trial_expires_at: started_at.advance(months: 1))
    end
  end

  def available_book_credits
    book_credits.visible.available.count
  end

  def available_character_credits
    character_credits.visible.available.count
  end

  def book_generation_available?
    return true if admin?
    return !trial_expired? && trial_books_remaining.positive? if trial?

    book_credits.spendable.exists?
  end

  def character_generation_available?
    return true if admin?
    if trial?
      return action_logs.for_action("setup_illustration").count < Character::TRIAL_USER_LIMIT
    end

    character_credits.spendable.exists?
  end
end
