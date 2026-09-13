require "test_helper"
require "minitest/mock"

class CharacterImageRequestTest < ActiveSupport::TestCase
  setup do
    @character = characters(:hernandes)
  end

  test "submission checks inputs before spending an image attempt" do
    attach_photo(@character, "source.png")
    assert_no_difference "ActionLog.count" do
      request = CharacterImageRequest.submit!(@character)
      assert_equal "checking", request.screening_status
      assert_equal request, @character.reload.current_image_request
      assert_nil request.generation_attempt
    end
  end

  test "identical same-owner inputs share assessment across characters and filenames" do
    attach_photo(@character, "first.png")
    other = @character.user.characters.create!(name: "Another child")
    attach_photo(other, "renamed.png")
    first = CharacterImageRequest.submit!(@character)
    second = CharacterImageRequest.submit!(other)
    assert_equal first.assessment_id, second.assessment_id
    assert_no_difference [ "CharacterImageRequest.count", "CharacterImageAssessment.count" ] do
      assert_equal first.id, CharacterImageRequest.submit!(@character).id
    end
  end

  test "another owner cannot reuse an assessment" do
    attach_photo(@character, "first.png")
    other = users(:two).characters.create!(name: "Someone else")
    attach_photo(other, "first.png")
    assert_not_equal CharacterImageRequest.submit!(@character).assessment_id,
      CharacterImageRequest.submit!(other).assessment_id
  end

  test "changed generation inputs supersede the old request" do
    first = CharacterImageRequest.submit!(@character)
    @character.update!(hair_color: "Red")
    second = CharacterImageRequest.submit!(@character)
    assert_not_equal first.id, second.id
    assert_not first.reload.current?
    assert second.current?
  end

  test "review is shared and its reason remains private" do
    attach_photo(@character, "source.png")
    first = CharacterImageRequest.submit!(@character)
    first.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private evidence")
    assert_equal "needs_review", first.reload.screening_status
    assert_nil first.public_reason
    assert_no_difference "CharacterImageDecision.count" do
      first.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "duplicate")
    end
    assert_equal [ "needs_review" ], @character.user.character_image_decisions.pluck(:outcome)
  end

  test "admin resolution preserves review history and reserves just one attempt" do
    attach_photo(@character, "source.png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private")
    admin = users(:three)
    admin.update!(admin: true)
    request.assessment.resolve!(outcome: "approved", source: "admin", reviewer: admin, internal_reason: "Reviewed")
    2.times { request.enqueue_generation! }
    assert_equal [ "needs_review", "approved" ], request.assessment.decisions.order(:id).pluck(:outcome)
    assert_equal 1, request.reload.generation_attempt.action_log.user.action_logs.for_action("setup_illustration").count
  end

  test "only admins resolve review and rejection requires a public reason" do
    attach_photo(@character, "source.png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private")
    assert_raises(ArgumentError) do
      request.assessment.resolve!(outcome: "approved", source: "admin", reviewer: users(:two), internal_reason: "no")
    end
    assert_raises(ArgumentError) do
      request.assessment.resolve!(outcome: "rejected", source: "automatic", internal_reason: "invalid")
    end
  end

  test "held request does not block the same owner's other generation" do
    attach_photo(@character, "source.png")
    held = CharacterImageRequest.submit!(@character)
    held.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private")
    other = @character.dup
    other.name = "Ready"
    other.hair_color = "Red"
    other.current_image_request_id = nil
    other.save!
    ready = CharacterImageRequest.submit!(other)
    ready.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    assert_nil held.reload.generation_attempt
    assert ready.reload.generation_attempt
  end

  test "screening does not spend exhausted generation quota" do
    Character::TRIAL_CHARACTER_LIMIT.times { @character.record_action!("setup_illustration") }
    request = CharacterImageRequest.submit!(@character)
    assert_no_difference "ActionLog.count" do
      request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "clear")
    end
    assert_nil request.reload.generation_attempt
    assert_equal "approved", request.screening_status
  end

  test "deleting a character retains user decision history and source" do
    attach_photo(@character, "retained.png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "rejected", source: "automatic", internal_reason: "invalid", public_reason: "Upload a readable photo.")
    @character.destroy!
    assert_nil request.reload.character_id
    assert_equal 1, users(:one).character_image_decisions.count
    assert request.assessment.photo.attached?
  end

  test "an expired screening worker cannot overwrite a newer claim" do
    attach_photo(@character, "source.png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.update!(claim_token: "new-worker")
    changed = request.assessment.resolve!(outcome: "approved", source: "automatic", internal_reason: "stale", expected_claim: "old-worker")
    assert_not changed
    assert_equal "checking", request.assessment.reload.status
    assert_nil request.generation_attempt
  end

  test "admin resolution preserves the original moderation evidence" do
    attach_photo(@character, "source.png")
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "flagged", metadata: { "id" => "mod_original", "scores" => { "violence" => 0.8 } })
    admin = users(:three)
    admin.update!(admin: true)
    request.assessment.resolve!(outcome: "approved", source: "admin", reviewer: admin, internal_reason: "Reviewed context")
    assert_equal "mod_original", request.assessment.reload.metadata["id"]
    assert_equal 0.8, request.assessment.metadata.dig("scores", "violence")
  end

  test "photo uploads do not emit frozen string deprecation warnings" do
    previous = Warning[:deprecated]
    Warning[:deprecated] = true

    _, stderr = capture_io { attach_photo(@character, "upload.png") }

    assert @character.photo.attached?
    assert_no_match(/literal string will be frozen/, stderr)
  ensure
    Warning[:deprecated] = previous
  end

  test "description prompt preserves categories and specifies an age appropriate fictional portrait" do
    @character.update!(age: 22, gender: "Girl", ethnicity: "White", hair_color: "Brown",
      hair_style: "Long", eye_color: "Brown", roles: [ "Hero", "Freckles" ])
    prompt = CharacterImageRequest.submit!(@character).assessment.prompt
    assert_includes prompt, "Character details:\n"
    details = JSON.parse(prompt.split("Character details:\n", 2).last)
    assert_equal({ "age" => 22, "gender" => "Girl", "ethnicity" => "White", "hair_color" => "Brown",
      "hair_style" => "Long", "eye_color" => "Brown", "roles" => [ "Hero", "Freckles" ] }, details)
    assert_includes prompt, "fictional"
    assert_includes prompt, "age-appropriate everyday clothing"
    assert_includes prompt, "numeric age"
  end

  private

  def attach_photo(character, name)
    character.photo.attach(io: StringIO.new("identical image bytes".b), filename: name, content_type: "image/png")
  end
end
