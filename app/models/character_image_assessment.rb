class CharacterImageAssessment < ApplicationRecord
  POLICY_VERSION = "1"
  OUTCOMES = %w[checking approved needs_review rejected unavailable].freeze

  belongs_to :user
  has_one_attached :photo
  has_many :requests, class_name: "CharacterImageRequest", foreign_key: :assessment_id
  has_many :decisions, class_name: "CharacterImageDecision", foreign_key: :assessment_id
  validates :status, inclusion: { in: OUTCOMES }
  attr_readonly :user_id, :fingerprint, :prompt, :generation_model, :policy_version

  def approve_without_screening!(notify: true)
    changed = false
    with_lock do
      return false if photo.attached? || status == "approved"
      update!(status: "approved", internal_reason: "screening_not_required", public_reason: nil, claim_token: nil, claimed_at: nil)
      decisions.create!(user: user, request: requests.order(:id).first, outcome: "approved", source: "automatic",
        internal_reason: "screening_not_required")
      changed = true
    end
    notify_requests! if changed && notify
    changed
  end

  def screening_unavailable!(reason:, expected_claim: nil)
    changed = false
    with_lock do
      return false unless status == "checking" && (!expected_claim || claim_token == expected_claim)
      failures = metadata.fetch("screening_failures", []) + [{ "reason" => reason, "recorded_at" => Time.current.iso8601 }]
      update!(status: "unavailable", internal_reason: reason, claim_token: nil, claimed_at: nil,
        metadata: metadata.merge("screening_failures" => failures))
      changed = true
    end
    notify_requests! if changed
    changed
  end

  def retry_screening!
    with_lock do
      return false unless status == "unavailable"
      update!(status: "checking", check_attempts: 0, claim_token: nil, claimed_at: nil)
    end
    job = ScreenCharacterImageJob.perform_later(id)
    return screening_retry_enqueue_failed! unless job&.successfully_enqueued?

    notify_requests!
    true
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    screening_retry_enqueue_failed!
  end

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
      CharacterFunding.release!(request, reason: "character_screening_rejected") if status == "rejected"
      if status == "approved"
        request.enqueue_generation!(release_on_failure: true,
          allow_reacquire: request.funding_source.nil?)
      end
      request.character.broadcast_image_status
    end
  end

  private

  def screening_retry_enqueue_failed!
    with_lock do
      update!(status: "unavailable", internal_reason: "screening_retry_enqueue_failed") if status == "checking"
    end
    requests.find_each do |request|
      next unless request.current?

      CharacterFunding.release!(request, reason: "character_screening_enqueue_failed")
    end
    notify_requests!
    false
  end
end
