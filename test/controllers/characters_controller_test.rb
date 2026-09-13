# frozen_string_literal: true

require "test_helper"

class CharactersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @user.tutorial.update!(terms: true)
    @character = characters(:hernandes)
    sign_in @user
  end

  test "index renders only the signed-in user's characters" do
    other_character = Character.create!(name: "Private", user: users(:two))

    get characters_url

    assert_response :success
    assert_select "h2", "Characters"
    assert_select "a[href='#{new_character_path}']", text: /New Character/
    assert_select "h2", text: @character.name
    assert_select "h2", text: other_character.name, count: 0
  end

  test "new renders both character creation modes" do
    get new_character_url

    assert_response :success
    assert_select "form[action='#{characters_path}']"
    assert_select "button#tab-photo", "Photo Upload"
    assert_select "button#tab-form", "Descriptive Form"
    assert_select "input[id^='character_roles_']", minimum: 1
  end

  test "edit preloads the uploaded character photo in the preview" do
    @character.photo.attach(
      io: File.open(file_fixture("character.png")),
      filename: "original-character.png",
      content_type: "image/png"
    )

    get edit_character_url(@character)

    assert_response :success
    assert_select "#content-photo:not(.hidden)"
    assert_select "#file-name-display", "original-character.png"
    assert_select "#photo-preview-container img[alt='Character Photo Preview']", 1 do |images|
      assert_includes images.first["src"], "/rails/active_storage/"
    end
  end

  test "roles are an optional final section with grouped accessible array inputs" do
    get new_character_url

    assert_select "#content-form + #character-roles", 1
    assert_select "#character-roles ~ div input[type='submit']", 1
    assert_select "#character-roles h2", "Roles & traits — optional"
    assert_select "#character-roles fieldset legend", text: "Family"
    assert_select "#character-roles fieldset legend", text: "Appearance"
    assert_select "#character-roles fieldset legend", text: "Story"
    assert_select "#character-roles input[type='checkbox'][name='character[roles][]']:not(.hidden):not([required])", 11
    assert_select "#character-roles input[value='Supporting']", 1
    assert_select "#character-roles input[value='Big sibling']", 1
    assert_select "#character-roles input[value='Middle sibling']", 1
    assert_select "#character-roles input[value='Younger sibling']", 1
  end

  test "edit preserves selections and the rendered empty value clears all roles" do
    @character.update!(roles: [ "Father", "Freckles", "Supporting" ])
    get edit_character_url(@character)

    assert_select "#character-roles input[type='checkbox'][checked]", 3
    assert_select "#character-roles input[type='hidden'][name='character[roles][]']", 1 do |inputs|
      patch character_url(@character), params: { character: { roles: [ inputs.first["value"] ] } }
    end

    assert_redirected_to characters_url
    assert_equal [], @character.reload.roles
  end

  test "conflicting roles show errors and preserve choices without starting generation" do
    assert_no_difference("Character.count") do
      assert_no_enqueued_jobs do
        post characters_url, params: { character: { name: "Conflicted", age: 9, gender: "Girl", ethnicity: "Asian",
          hair_color: "Black", hair_style: "Long", eye_color: "Brown", creation_mode: "form",
          roles: [ "Mother", "Big sibling", "Hero", "Supporting" ] } }
      end
    end

    assert_response :unprocessable_content
    assert_select "#character-roles [role='alert']", text: /Choose only one family role/
    assert_select "#character-roles [role='alert']", text: /Choose only one story role/
    assert_select "#character-roles input[type='checkbox'][checked]", 4
  end

  test "photo creation accepts optional roles and retains them as metadata" do
    post characters_url, params: { character: { name: "Photo character", creation_mode: "photo",
      photo_upload: fixture_file_upload("character.png", "image/png"), roles: [ "Younger sibling", "Supporting" ] } }

    assert_redirected_to characters_url
    assert_equal [ "Younger sibling", "Supporting" ], @user.characters.find_by!(name: "Photo character").roles
  end

  test "create saves a descriptive character and queues image generation" do
    params = { character: { name: "Elara", age: 9, gender: "Girl", ethnicity: "Asian",
                            hair_color: "Black", hair_style: "Long", eye_color: "Brown",
                            creation_mode: "form", roles: [ "Hero" ] } }

    assert_difference("Character.count", 1) do
      assert_enqueued_jobs 1 do
        post characters_url, params: params
      end
    end

    character = Character.find_by!(name: "Elara", user: @user)
    assert_equal [ "Hero" ], character.roles
    assert_redirected_to characters_url
  end

  test "create renders validation errors for an incomplete descriptive character" do
    post characters_url, params: { character: { name: "Elara", creation_mode: "form" } }

    assert_response :unprocessable_content
    assert_select "p", text: "can't be blank", minimum: 1
  end

  test "does not expose another user's character" do
    other_character = Character.create!(name: "Private", user: users(:two))

    get character_url(other_character)

    assert_response :not_found
  end
end
