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
end
