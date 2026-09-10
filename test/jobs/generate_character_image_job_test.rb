require "test_helper"
require "minitest/mock"

class GenerateCharacterImageJobTest < ActiveJob::TestCase
  setup do
    @character = characters(:hernandes)
    @request = CharacterImageRequest.submit!(@character)
    @request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    @attempt = @request.reload.generation_attempt
  end

  test "duplicate delivery generates and counts usage once" do
    calls = 0
    CharacterImageGeneration.stub :call, ->(_) { calls += 1; image_result } do
      2.times { GenerateCharacterImageJob.perform_now(@attempt.id) }
    end
    assert_equal 1, calls
    assert_equal "completed", @attempt.reload.status
    assert @attempt.result_image.attached?
    assert @character.reload.completed?
    assert @character.illustration.original_image.present?
    assert_equal 1, @character.user.action_logs.for_action("setup_illustration").count
  end

  test "changed input prevents stale paid work" do
    @character.update!(hair_color: "Red")
    CharacterImageRequest.submit!(@character)
    CharacterImageGeneration.stub :call, ->(_) { flunk "stale request must not generate" } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert_not @character.reload.completed?
  end

  test "a provider timeout is not automatically resubmitted" do
    calls = 0
    CharacterImageGeneration.stub :call, ->(_) { calls += 1; raise Timeout::Error } do
      2.times { GenerateCharacterImageJob.perform_now(@attempt.id) }
    end
    assert_equal 1, calls
    assert_equal "outcome_unknown", @attempt.reload.status
    assert_equal "approved", @request.reload.screening_status
  end

  test "provider refusal becomes a public rejection with retained approval history" do
    error = CharacterImageGeneration::Refused.new(public_reason: "The image service declined this request.", metadata: { "code" => "moderation_blocked" })
    CharacterImageGeneration.stub :call, ->(_) { raise error } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert_equal "rejected", @request.reload.screening_status
    assert_match(/declined/, @request.public_reason)
    assert_equal [ "approved", "rejected" ], @request.assessment.decisions.order(:id).pluck(:outcome)
    assert_equal "approved", @request.assessment.status
  end

  test "late result never overwrites a changed character" do
    CharacterImageGeneration.stub :call, ->(_) {
      @character.update!(hair_color: "Red")
      CharacterImageRequest.submit!(@character)
      image_result
    } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert @attempt.reload.result_image.attached?
    assert_not @character.reload.completed?
  end

  test "changed persisted input cannot use an old approval even before submission finishes" do
    @character.update!(hair_color: "Red")
    CharacterImageGeneration.stub :call, ->(_) { flunk "changed input must not use previous approval" } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert_not @character.reload.completed?
  end

  test "returned bytes recover local failure without another provider call" do
    @attempt.result_image.attach(**image_result)
    @attempt.update!(status: "failed")
    CharacterImageGeneration.stub :call, ->(_) { flunk "returned result must be reused" } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert_equal "completed", @attempt.reload.status
  end

  test "returning to previously completed inputs reuses the image without paying again" do
    CharacterImageGeneration.stub :call, ->(_) { image_result } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    @character.reload.update!(hair_color: "Red")
    CharacterImageRequest.submit!(@character)
    @character.update!(hair_color: "Black")
    assert_no_difference "ActionLog.count" do
      assert_equal @request.id, CharacterImageRequest.submit!(@character).id
    end
    assert @character.reload.completed?
    assert_equal @attempt.reload.illustration_id, @character.illustration.id
  end

  test "a late result can be published locally when its inputs are selected again" do
    CharacterImageGeneration.stub :call, ->(_) {
      @character.update!(hair_color: "Red")
      CharacterImageRequest.submit!(@character)
      image_result
    } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    @character.update!(hair_color: "Black")
    assert_enqueued_with(job: GenerateCharacterImageJob, args: [ @attempt.id ]) do
      CharacterImageRequest.submit!(@character)
    end
    CharacterImageGeneration.stub :call, ->(_) { flunk "reuse the late result without another paid call" } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert @character.reload.completed?
  end

  test "deleting a character during generation retains the result and accounting" do
    CharacterImageGeneration.stub :call, ->(_) { @character.destroy!; image_result } do
      GenerateCharacterImageJob.perform_now(@attempt.id)
    end
    assert_nil @request.reload.character_id
    assert @attempt.reload.result_image.attached?
    assert @attempt.action_log.persisted?
  end

  test "provider bad requests retain diagnostic metadata and are not uncertain outcomes" do
    error = Faraday::BadRequestError.new("Bad request", status: 400,
      headers: { "x-request-id" => "req_invalid_model" },
      body: { "error" => { "code" => "invalid_value", "param" => "model", "message" => "private detail" } }.to_json)
    CharacterImageGeneration.stub :call, ->(_) { raise error } do
      2.times { GenerateCharacterImageJob.perform_now(@attempt.id) }
    end
    assert_equal "failed", @attempt.reload.status
    assert_equal "invalid_value", @attempt.failure_metadata["code"]
    assert_equal "model", @attempt.failure_metadata["param"]
    assert_equal 400, @attempt.failure_metadata["http_status"]
    assert_equal "req_invalid_model", @attempt.failure_metadata["request_id"]
    assert_not_includes @attempt.failure_metadata.to_json, "private detail"
    assert_equal "approved", @request.reload.screening_status
  end

  private

  def image_result
    bytes = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")
    { io: StringIO.new(bytes), filename: "character.png", content_type: "image/png" }
  end
end
