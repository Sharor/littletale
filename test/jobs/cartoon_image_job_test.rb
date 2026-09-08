require "test_helper"
require "minitest/mock"

class CartoonImageJobTest < ActiveJob::TestCase
  test "legacy photo jobs go through screening without calling image generation" do
    character = characters(:hernandes)
    Illustration.stub :where, ->(*) { flunk "legacy jobs must not bypass screening" } do
      assert_no_difference "ActionLog.count" do
        assert_enqueued_with(job: ScreenCharacterImageJob) do
          CartoonImageJob.perform_now(character.id, "frontend-id")
        end
      end
    end
    assert_equal "checking", character.reload.current_image_request.screening_status
  end
end
