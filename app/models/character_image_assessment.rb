class CharacterImageAssessment < ApplicationRecord
  POLICY_VERSION = "1"
  OUTCOMES = %w[checking approved needs_review rejected].freeze

  belongs_to :user
  has_one_attached :photo
  has_many :requests, class_name: "CharacterImageRequest", foreign_key: :assessment_id
  has_many :decisions, class_name: "CharacterImageDecision", foreign_key: :assessment_id
  validates :status, inclusion: { in: OUTCOMES }
  attr_readonly :user_id, :fingerprint, :prompt, :generation_model, :policy_version

  def resolve!(outcome:, source:, internal_reason:, public_reason: nil, reviewer: nil, metadata: nil, expected_claim: nil)
    raise ArgumentError, "Invalid decision" unless %w[approved needs_review rejected].include?(outcome)
    raise ArgumentError, "A public rejection reason is required" if outcome == "rejected" && public_reason.blank?
    raise ArgumentError, "Administrator required" if source == "admin" && !reviewer&.admin?
    changed = false
    with_lock do
      allowed = source == "admin" ? status == "needs_review" : status == "checking"
      allowed &&= claim_token == expected_claim if expected_claim
      if allowed
        update!(status: outcome, internal_reason: internal_reason,
          public_reason: outcome == "rejected" ? public_reason : nil, metadata: metadata || self.metadata,
          claim_token: nil, claimed_at: nil)
        decisions.create!(user: user, request: requests.order(:id).first,
          reviewer: reviewer, outcome: outcome, source: source,
          internal_reason: internal_reason, public_reason: self.public_reason)
        changed = true
      end
    end
    notify_requests! if changed
    changed
  end

  def notify_requests!
    requests.find_each do |request|
      next unless request.current?
      request.enqueue_generation! if status == "approved"
      request.character.broadcast_image_status
    end
  end
end
