require "test_helper"

class AdminCharacterRetryTest < ActiveJob::TestCase
  setup do
    @admin = users(:three)
    @admin.update!(admin: true)
    @request = CharacterImageRequest.submit!(characters(:hernandes))
    @attempt = @request.reload.generation_attempt
    @attempt.update!(status: "failed", failure_metadata: { "code" => "content_filter" })
    @request.reject_by_provider!(public_reason: "Declined")
  end

  test "admin retry preserves history and prevents duplicate submissions" do
    token = @attempt.updated_at.iso8601(6)
    assert_enqueued_with(job: GenerateCharacterImageJob, args: [@attempt.id]) do
      assert @request.admin_retry_generation!(admin: @admin, expected_version: token)
    end
    assert_equal "reserved", @attempt.reload.status
    assert_equal "approved", @request.reload.screening_status
    assert_equal "content_filter", @attempt.failure_metadata.dig("admin_history", 0, "failure_metadata", "code")
    assert_equal @admin.id, @attempt.failure_metadata["requested_by_admin_id"]
    assert_not @request.admin_retry_generation!(admin: @admin, expected_version: token)
  end

  test "rejects unauthorized stale and unconfirmed unknown retries" do
    token = @attempt.updated_at.iso8601(6)
    assert_raises(ArgumentError) { @request.admin_retry_generation!(admin: users(:one), expected_version: token) }
    @attempt.update!(status: "outcome_unknown")
    assert_not @request.admin_retry_generation!(admin: @admin, expected_version: @attempt.updated_at.iso8601(6))
    @request.character.update!(hair_color: "Red")
    assert_not @request.admin_retry_generation!(admin: @admin, expected_version: @attempt.updated_at.iso8601(6), confirm_unknown: true)
  end

  test "saved failed image is reused and completed result remains until replacement" do
    @attempt.result_image.attach(io: File.open(file_fixture("character.png")), filename: "character.png", content_type: "image/png")
    blob_id = @attempt.result_image.blob.id
    assert @request.admin_retry_generation!(admin: @admin, expected_version: @attempt.updated_at.iso8601(6))
    assert_equal blob_id, @attempt.reload.result_image.blob.id
    GenerateCharacterImageJob.perform_now(@attempt.id)
    assert_equal "completed", @attempt.reload.status
    previous = @request.character.reload.illustration
    assert @request.admin_retry_generation!(admin: @admin, expected_version: @attempt.updated_at.iso8601(6))
    assert_equal previous.id, @request.character.reload.illustration.id
    assert_not @attempt.reload.result_image.attached?
    assert_equal previous.id, @attempt.failure_metadata["admin_history"].last["illustration_id"]
  end

  test "screening holds cannot be bypassed by admin generation retry" do
    @request.assessment.update!(status: "needs_review")
    assert_not @request.admin_retry_generation!(admin: @admin, expected_version: @attempt.updated_at.iso8601(6))
  end
end
