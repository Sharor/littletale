require "test_helper"
require "minitest/mock"

class ScreenCharacterImageJobTest < ActiveJob::TestCase
  setup do
    characters(:hernandes).photo.attach(io: File.open(file_fixture("character.png")), filename: "source.png", content_type: "image/png")
  end

  test "legacy form review is bypassed without screening and preserves history" do
    character = characters(:hernandes)
    character.photo.purge
    snapshot = CharacterImageRequest.snapshot_for(character)
    assessment = CharacterImageAssessment.create!(**snapshot, user: character.user, policy_version: "1", status: "checking")
    request = CharacterImageRequest.create!(assessment: assessment, user: character.user,
      character: character, original_character_id: character.id)
    character.update!(current_image_request: request)
    assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "Screening unavailable")
    CharacterImageModeration.stub :call, ->(*) { flunk "form characters must bypass screening" } do
      assert_difference "ActionLog.count", 1 do
        2.times { ScreenCharacterImageJob.perform_now(assessment.id) }
      end
    end
    assert_equal "approved", assessment.reload.status
    assert_equal %w[needs_review approved], assessment.decisions.order(:id).pluck(:outcome)
    assert_equal "screening_not_required", assessment.internal_reason
  end

  test "duplicate jobs screen once and do not charge a held request" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    calls = 0
    CharacterImageModeration.stub :call, ->(_) {
      calls += 1
      { outcome: "needs_review", internal_reason: "private evidence", metadata: {} }
    } do
      assert_no_difference "ActionLog.count" do
        2.times { ScreenCharacterImageJob.perform_now(request.assessment_id) }
      end
    end
    assert_equal 1, calls
    assert_equal "needs_review", request.reload.screening_status
  end

  test "screening errors become unavailable rather than requiring human review" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    calls = 0
    CharacterImageModeration.stub :call, ->(_) { calls += 1; raise Timeout::Error } do
      4.times { ScreenCharacterImageJob.perform_now(request.assessment_id) }
    end
    assert_equal 3, calls
    assert_equal "unavailable", request.reload.screening_status
    assert_empty request.assessment.decisions
    assert_nil request.generation_attempt
  end
end
