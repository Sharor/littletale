require "test_helper"
require "minitest/mock"

class GenerateImageJobTest < ActiveJob::TestCase
  test "legacy description jobs screen current inputs instead of generating an old prompt" do
    character = characters(:hernandes)
    Illustration.stub :where, ->(*) { flunk "legacy jobs must not bypass screening" } do
      assert_no_difference "ActionLog.count" do
        assert_enqueued_with(job: ScreenCharacterImageJob) do
          GenerateImageJob.perform_now(character.id, "Old queued prompt")
        end
      end
    end
    assert_not_includes character.reload.current_image_request.assessment.prompt, "Old queued prompt"
  end
end
