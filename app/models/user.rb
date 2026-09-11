# frozen_string_literal: true

class User < ApplicationRecord
  has_many :books, dependent: :nullify
  has_many :visits, class_name: "Visitor"
  has_many :events, through: :visits
  has_many :action_logs
  has_many :characters
  has_many :character_image_assessments
  has_many :character_image_requests
  has_many :character_image_decisions
  has_one :tutorial

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
end
