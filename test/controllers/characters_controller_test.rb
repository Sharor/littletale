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
    assert_select "main.fable-character-overview"
    assert_select "form .fable-character-overview-header + .fable-character-grid"
    assert_select ".fable-character-overview-header button.fable-character-book-cta[type='submit'] span:first-child",
      I18n.t("characters.index.make_book_without_characters")
    assert_select "a[href='#{new_character_path}']", text: /New Character/
    assert_select "h2", text: @character.name
    assert_select "h2", text: other_character.name, count: 0
    assert_select "input[type='checkbox'][aria-label=?]:not(.hidden)", "Select #{@character.name}"
    assert_select "a[href='#{edit_character_path(@character)}'][aria-label=?]", "Edit #{@character.name}"
    assert_select "a[href='#{confirm_delete_character_path(@character)}'][aria-label=?]", "Delete #{@character.name}"
  end

  test "new renders both character creation modes" do
    get new_character_url

    assert_response :success
    assert_select "form[action='#{characters_path}']"
    assert_select "button#tab-photo", "Photo Upload"
    assert_select "button#tab-form", "Descriptive Form"
    %w[name age gender ethnicity hair_style hair_color eye_color].each do |field|
      assert_select "label.fable-form-label[for='character_#{field}']", count: 1
    end
    assert_select "#character-roles fieldset legend.fable-form-legend", count: Character::ROLE_GROUPS.size
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
    assert_select "#character-creation-container.fable-character-editor"
    assert_select "#content-photo:not(.hidden)"
    assert_select "#file-name-display", "original-character.png"
    assert_select "#photo-preview-container .fable-photo-preview-frame img.fable-photo-preview-image[alt='Character Photo Preview']", 1 do |images|
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

  test "approval mode saves a character without spending funding or queueing generation" do
    @user.create_parent_control!(enabled: true, mode: "approval_required", pin: "4826", pin_confirmation: "4826")
    params = { character: { name: "Waiting hero", age: 9, gender: "Girl", ethnicity: "Asian",
      hair_color: "Black", hair_style: "Long", eye_color: "Brown", creation_mode: "form", roles: [ "Hero" ] } }

    assert_difference("Character.count", 1) do
      assert_no_enqueued_jobs do
        post characters_url, params: params
      end
    end

    character = @user.characters.find_by!(name: "Waiting hero")
    assert_predicate character, :awaiting_parental_approval?
    assert_nil character.current_image_request
    assert_redirected_to characters_url
  end

  test "daily mode lets existing character credits govern generation" do
    @user.user_subscriptions.create!(status: "active", product_id: UserSubscription::PRODUCT_ID,
      idempotency_key: SecureRandom.uuid)
    @user.create_parent_control!(enabled: true, mode: "daily_limit", daily_book_limit: 1,
      pin: "4826", pin_confirmation: "4826")
    params = { character: { name: "Daily hero", age: 9, gender: "Girl", ethnicity: "Asian",
      hair_color: "Black", hair_style: "Long", eye_color: "Brown", creation_mode: "form", roles: [ "Hero" ] } }

    assert_enqueued_jobs 1 do
      post characters_url, params: params
    end

    assert_not @user.characters.find_by!(name: "Daily hero").awaiting_parental_approval?
  end

  test "changing a failed approved character creates a new approval request" do
    @user.create_parent_control!(enabled: true, mode: "approval_required", pin: "4826", pin_confirmation: "4826")
    request = ParentalGenerationGate.authorize(@character).request
    request.approve!
    @character.update!(generation_status: :failed)

    assert_no_enqueued_jobs do
      patch character_url(@character), params: { character: {
        name: @character.name, age: @character.age, gender: @character.gender, ethnicity: @character.ethnicity,
        hair_color: @character.hair_color, hair_style: @character.hair_style, eye_color: "Blue",
        creation_mode: "form", roles: @character.roles
      } }
    end

    assert_predicate @character.reload, :awaiting_parental_approval?
    assert_equal "released", request.reload.status
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
  test "deleting a character preserves its record image and existing book membership" do
    illustration_id = @character.illustration.id
    book = @character.books.first
    @character.photo.attach(io: File.open(file_fixture("character.png")),
      filename: "character.png", content_type: "image/png")

    assert_no_difference(["Character.count", "Illustration.count"]) do
      delete character_url(@character), as: :turbo_stream
    end

    assert_response :success
    assert_not_nil @character.reload.deleted_at
    assert_equal illustration_id, @character.illustration.id
    assert @character.photo.attached?
    assert_includes book.reload.characters, @character
    assert_select "turbo-stream[action='remove'][target='character_#{@character.id}']"
    assert_select "turbo-stream[action='update'][target='modal']"

    get characters_url
    assert_select "#character_#{@character.id}", count: 0
    get character_url(@character)
    assert_response :not_found
    get select_characters_url(book_id: book.id)
    assert_select "input[value='#{@character.id}']", count: 0
    get new_book_url(character_ids: [@character.id])
    assert_response :unprocessable_content
    post save_selected_characters_url, params: { book_id: book.id, character_ids: [@character.id] }
    assert_response :unprocessable_content
  end

  test "deleting a character releases its pending parent approval" do
    @user.create_parent_control!(enabled: true, pin: "4826", pin_confirmation: "4826")
    request = ParentalGenerationGate.authorize(@character).request

    delete character_url(@character)

    assert_redirected_to characters_url
    assert_equal "released", request.reload.status
  end

  test "HTML deletion returns to the character list" do
    delete character_url(@character)

    assert_response :see_other
    assert_redirected_to characters_url
    assert_not_nil @character.reload.deleted_at
  end

  test "cannot delete another user's character" do
    character = Character.create!(name: "Private", user: users(:two))

    delete character_url(character), as: :turbo_stream

    assert_response :not_found
    assert Character.exists?(character.id)
  end

end
