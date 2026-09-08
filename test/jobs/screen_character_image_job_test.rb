require "test_helper"
require "minitest/mock"

class ScreenCharacterImageJobTest < ActiveJob::TestCase
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

  test "screening errors hold after bounded retries" do
    request = CharacterImageRequest.submit!(characters(:hernandes))
    calls = 0
    CharacterImageModeration.stub :call, ->(_) { calls += 1; raise Timeout::Error } do
      4.times { ScreenCharacterImageJob.perform_now(request.assessment_id) }
    end
    assert_equal 3, calls
    assert_equal "needs_review", request.reload.screening_status
    assert_nil request.generation_attempt
  end
end
