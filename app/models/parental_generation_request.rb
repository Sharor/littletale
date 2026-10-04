# frozen_string_literal: true

class ParentalGenerationRequest < ApplicationRecord
  STATUSES = %w[pending approved declined released completed].freeze
  KINDS = %w[book character].freeze

  belongs_to :parent_control
  belongs_to :user
  belongs_to :generatable, polymorphic: true

  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  validates :policy_mode, inclusion: { in: ParentControl::MODES }
  validates :request_key, presence: true
  validate :ownership_is_consistent

  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }

  def pending? = status == "pending"
  def approved? = status == "approved"

  def approve!
    update!(status: "approved", decided_at: Time.current)
    self
  end

  def decline!
    update!(status: "declined", decided_at: Time.current)
    self
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
    self
  end

  def release!
    update!(status: "released")
    self
  end

  private

  def ownership_is_consistent
    return unless parent_control && user && generatable

    errors.add(:user, "must own the parent control") unless parent_control.user == user
    errors.add(:generatable, "must belong to the same user") unless generatable.user == user
  end
end
