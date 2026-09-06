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
