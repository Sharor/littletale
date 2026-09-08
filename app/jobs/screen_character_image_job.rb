class ScreenCharacterImageJob < ApplicationJob
  queue_as :default

  def perform(assessment_id)
    assessment = CharacterImageAssessment.find_by(id: assessment_id)
    return unless assessment
    token = SecureRandom.uuid
    claimed = false
    assessment.with_lock do
      if assessment.status == "checking" && assessment.claim_token.nil?
        assessment.update!(claim_token: token, claimed_at: Time.current, check_attempts: assessment.check_attempts + 1)
        claimed = true
      end
    end
    return unless claimed
    result = CharacterImageModeration.call(assessment)
    assessment.resolve!(**result, source: "automatic", expected_claim: token)
  rescue StandardError => error
    raise unless claimed
    retry_check = false
    assessment.with_lock do
      return unless assessment.claim_token == token && assessment.status == "checking"
      if assessment.check_attempts < 3
        assessment.update!(claim_token: nil, claimed_at: nil)
        retry_check = true
      end
    end
    if retry_check
      self.class.set(wait: assessment.check_attempts.minutes).perform_later(assessment.id)
    else
      assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "Screening unavailable (#{error.class.name})", expected_claim: token)
    end
  end
end
