require "test_helper"

class Admin::CharactersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "only admins can list or restore deleted characters" do
    get "/admin/characters"
    assert_response :forbidden
    post "/admin/characters/#{characters(:hernandes).id}/restore"
    assert_response :forbidden

    sign_in users(:one)
    get "/admin/characters"
    assert_response :forbidden
    post "/admin/characters/#{characters(:hernandes).id}/restore"
    assert_response :forbidden
  end

  test "an admin can restore a deleted character with its original image and books" do
    character = characters(:hernandes)
    owner = users(:one)
    owner.tutorial.update!(terms: true)
    book = character.books.first
    illustration_id = character.illustration.id
    sign_in owner
    delete character_path(character)

    admin = users(:three)
    admin.update!(admin: true)
    sign_in admin
    get "/admin/characters"
    assert_response :success
    assert_select "article", text: /#{Regexp.escape(character.name)}/
    assert_select "form[action='/admin/characters/#{character.id}/restore']"

    post "/admin/characters/#{character.id}/restore"
    assert_response :see_other
    assert_redirected_to "/admin/characters"
    assert_nil character.reload.deleted_at
    assert_equal illustration_id, character.illustration.id
    assert_includes book.reload.characters, character

    sign_in owner
    get characters_path
    assert_select "#character_#{character.id}"
  end

  test "an admin can manage deleted characters in Spanish" do
    admin = users(:three)
    admin.update!(admin: true, language: "es")
    sign_in admin

    get admin_characters_url

    assert_response :success
    assert_select "h1", "Personajes eliminados"
  end
end
