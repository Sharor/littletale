class RecoverCharacterImagesJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = 1.hour.ago
    CharacterImageAssessment.where(status: "checking").find_each do |assessment|
      recover_check = false
      exhausted = false
      assessment.with_lock do
        if assessment.status == "checking" && (assessment.claimed_at.nil? || assessment.claimed_at < cutoff)
          exhausted = assessment.check_attempts >= 3
          assessment.update!(claim_token: nil, claimed_at: nil)
          recover_check = !exhausted
        end
      end
      if exhausted
        assessment.screening_unavailable!(reason: "Screening attempts exhausted after worker interruption")
      elsif recover_check
        ScreenCharacterImageJob.perform_later(assessment.id)
      end
    end

    CharacterImageGenerationAttempt.where(status: "in_progress").where("started_at < ?", cutoff).find_each do |attempt|
      attempt.with_lock do
        if attempt.status == "in_progress" && attempt.started_at < cutoff
          attempt.update!(status: attempt.result_image.attached? ? "failed" : "outcome_unknown",
            finished_at: Time.current, failure_metadata: { "error_class" => "WorkerInterrupted" })
        end
      end
      if attempt.request.current?
        attempt.request.character.failed!
        attempt.request.character.broadcast_image_status
      end
    end

    CharacterImageRequest.joins(:assessment).where(character_image_assessments: { status: "approved" }, provider_rejected: false).find_each do |request|
      request.enqueue_generation!
    end
  end
end
