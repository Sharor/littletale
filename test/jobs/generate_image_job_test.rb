require "test_helper"
require "minitest/mock"

class GenerateImageJobTest < ActiveJob::TestCase
  test "legacy description jobs bypass screening and generate from current inputs" do
    character = characters(:hernandes)
    Illustration.stub :where, ->(*) { flunk "legacy jobs must use tracked generation" } do
      assert_difference "ActionLog.count", 1 do
        assert_enqueued_with(job: GenerateCharacterImageJob) do
          GenerateImageJob.perform_now(character.id, "Old queued prompt")
        end
      end
    end
    assert_not_includes character.reload.current_image_request.assessment.prompt, "Old queued prompt"
  end
end
