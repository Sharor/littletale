require "test_helper"
require "minitest/mock"

class RecoverCharacterImagesJobTest < ActiveJob::TestCase
  test "abandoned paid attempts become unknown without being submitted again" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    attempt = request.reload.generation_attempt
    attempt.update!(status: "in_progress", started_at: 2.hours.ago)
    assert_no_enqueued_jobs only: GenerateCharacterImageJob do
      RecoverCharacterImagesJob.perform_now
    end
    assert_equal "outcome_unknown", attempt.reload.status
  end

  test "abandoned screening claims can be recovered without paid generation" do
    characters(:hernandes).photo.attach(io: File.open(file_fixture("character.png")), filename: "source.png", content_type: "image/png")
    request = CharacterImageRequest.submit!(characters(:hernandes))
    request.assessment.update!(claim_token: "abandoned", claimed_at: 2.hours.ago, check_attempts: 1)
    assert_enqueued_with(job: ScreenCharacterImageJob, args: [ request.assessment_id ]) do
      RecoverCharacterImagesJob.perform_now
    end
    assert_nil request.assessment.reload.claim_token
    assert_nil request.generation_attempt
  end

  test "lost enqueue of an approved request is recovered once with the same usage reservation" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    attempt = request.reload.generation_attempt
    assert_no_difference "ActionLog.count" do
      assert_enqueued_with(job: GenerateCharacterImageJob, args: [ attempt.id ]) do
        RecoverCharacterImagesJob.perform_now
      end
    end
  end

  test "stale rejected description is retried once with the current safe prompt" do
    character = characters(:hernandes)
    rejected = CharacterImageRequest.submit!(character)
    rejected.enqueue_generation!
    attempt = rejected.generation_attempt
    original_failure = { "code" => "moderation_blocked", "request_id" => "req_old",
      "category" => "sexual" }
    attempt.update!(status: "failed", finished_at: Time.current, failure_metadata: original_failure)
    rejected.reject_by_provider!(public_reason: "The image service declined this request.",
      metadata: original_failure)

    assert_no_difference [ "CharacterImageRequest.count", "CharacterImageGenerationAttempt.count", "ActionLog.count" ] do
      assert_enqueued_with(job: GenerateCharacterImageJob) do
        RecoverCharacterImagesJob.perform_now
      end
    end

    replacement = character.reload.current_image_request
    assert_equal rejected.id, replacement.id
    assert_equal "approved", replacement.screening_status
    assert_not replacement.provider_rejected?
    assert_equal "reserved", attempt.reload.status
    assert_equal CharacterImageGeneration::DESCRIPTION_PROMPT_VERSION,
      attempt.failure_metadata["description_prompt_version"]
    assert_equal [ original_failure ], attempt.failure_metadata["prior_refusals"]

    attempt.update!(status: "failed", finished_at: Time.current,
      failure_metadata: attempt.failure_metadata.merge("code" => "moderation_blocked", "category" => "sexual"))
    replacement.reject_by_provider!(public_reason: "The image service declined this request.",
      metadata: attempt.failure_metadata)
    assert_no_difference [ "CharacterImageRequest.count", "CharacterImageGenerationAttempt.count" ] do
      assert_no_enqueued_jobs only: GenerateCharacterImageJob do
        RecoverCharacterImagesJob.perform_now
      end
    end
  end
end
