require "test_helper"

class CharacterScreeningTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @character = characters(:hernandes)
    @character.photo.attach(io: File.open(file_fixture("character.png")), filename: "source.png", content_type: "image/png")
    sign_in @user
  end

  test "description creation bypasses screening and reserves image generation" do
    assert_difference "ActionLog.count", 1 do
      assert_no_enqueued_jobs(only: ScreenCharacterImageJob) do
        post characters_url, params: { character: { name: "Screen me", creation_mode: "form", age: 8,
          gender: "Girl", ethnicity: "Asian", hair_color: "Black", hair_style: "Long", eye_color: "Brown" } }
      end
    end
    request = Character.find_by!(name: "Screen me").current_image_request
    assert_equal "approved", request.screening_status
    assert_equal "screening_not_required", request.assessment.internal_reason
    assert request.generation_attempt
  end

  test "owner sees review status without private evidence" do
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private moderation evidence")
    get characters_url
    assert_response :success
    assert_includes response.body, "waiting for an administrator"
    assert_not_includes response.body, "private moderation evidence"
  end

  test "owner sees rejection explanation and replacement action" do
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "rejected", source: "automatic", internal_reason: "decode failed", public_reason: "Please upload a readable image.")
    get characters_url
    assert_includes response.body, "Please upload a readable image."
    assert_select "a[href='#{edit_character_path(@character)}']", text: /Replace|Edit/
    assert_not_includes response.body, "decode failed"
  end

  test "name-only edit reuses the request and does not charge again" do
    request = CharacterImageRequest.submit!(@character)
    assert_no_difference [ "CharacterImageRequest.count", "ActionLog.count" ] do
      patch character_url(@character), params: { character: { name: "Renamed" } }
    end
    assert_redirected_to characters_url
    assert_equal request.id, @character.reload.current_image_request_id
  end

  test "status broadcasts use an owner-scoped stream" do
    assert_broadcasts(@user.to_gid_param + ":characters", 1) do
      @character.broadcast_image_status
    end
  end

  test "replacement form updates the existing character" do
    get edit_character_url(@character)
    assert_response :success
    assert_select "form[action='#{character_path(@character)}']"
    assert_select "input[name='character[creation_mode]']"
  end

  test "JSON exposes only public screening state" do
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private moderation evidence")
    get character_url(@character, format: :json)
    assert_response :success
    assert_equal "needs_review", response.parsed_body.fetch("screening_status")
    assert_not_includes response.body, "private moderation evidence"
  end

  test "character selection renders screening status without private reasons" do
    request = CharacterImageRequest.submit!(@character)
    request.assessment.resolve!(outcome: "needs_review", source: "automatic", internal_reason: "private moderation evidence")
    get select_characters_url, params: { book_id: books(:one).id }
    assert_response :success
    assert_includes response.body, "waiting for an administrator"
    assert_not_includes response.body, "private moderation evidence"
  end

  test "switching to description mode removes the current photo but retains screening evidence" do
    @character.photo.attach(io: StringIO.new("original photo".b), filename: "original.png", content_type: "image/png")
    original = CharacterImageRequest.submit!(@character)
    patch character_url(@character), params: { character: { creation_mode: "form", age: 8, gender: "Girl", ethnicity: "Asian", hair_color: "Black", hair_style: "Long", eye_color: "Brown" } }
    assert_redirected_to characters_url
    assert_not @character.reload.photo.attached?
    assert original.assessment.photo.attached?
    assert_equal "gpt-image-1", @character.current_image_request.assessment.generation_model
  end

  test "Turbo replacement submission redirects to the updated character list" do
    CharacterImageRequest.submit!(@character)
    patch character_url(@character), params: { character: { name: "Updated through Turbo" } }, as: :turbo_stream
    assert_response :see_other
    assert_redirected_to characters_url
  end

  test "Turbo selection closes the chooser after selecting a ready character" do
    @character.update!(generation_status: :completed)
    @character.illustration.update!(original_image: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/character.png"), "image/png"))
    post save_selected_characters_url, params: { book_id: books(:one).id, character_ids: [ @character.id ] }, as: :turbo_stream
    assert_response :success
    assert_includes response.body, 'target="character_select_modal"'
  end
end
