# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CharacterTest < ActiveSupport::TestCase
  test "broadcasts character status in the owner's language" do
    character = characters(:hernandes)
    character.user.update!(language: "da")
    rendered_locale = nil

    character.stub :broadcast_replace_to, ->(*) { rendered_locale = I18n.locale } do
      character.broadcast_image_status
    end

    assert_equal :da, rendered_locale
    assert_equal :en, I18n.locale
  end

  test "roles are optional and persist as an empty list" do
    character = characters(:hernandes)
    [ [], nil, [ "", " " ] ].each do |roles|
      character.roles = roles
      assert character.valid?
      assert_equal [], character.roles
      character.save!
      assert_equal [], character.reload.roles
    end
  end

  test "roles normalize spelling blanks and duplicates without losing selections" do
    character = characters(:hernandes)
    character.update!(roles: [ " father ", "", "Father", " VILLAIN ", "Piercings" ])

    assert_equal [ "Father", "Villain", "Piercings" ], character.reload.roles
  end

  test "roles reject unknown values and anything other than a list of strings" do
    character = characters(:hernandes)
    [ "Father", { "family" => "Father" }, [ "Wizard" ], [ 1 ], [ nil ], [ [ "Father" ] ] ].each do |roles|
      character.roles = roles
      assert_not character.valid?, "Expected invalid roles: #{roles.inspect}"
      assert character.errors[:roles].any?
    end
  end

  test "every pair of family roles conflicts in both creation modes" do
    character = characters(:hernandes)
    character.photo.attach(io: File.open(file_fixture("character.png")), filename: "character.png", content_type: "image/png")
    %w[form photo].each do |mode|
      character.creation_mode = mode
      [ "Father", "Mother", "Big sibling", "Middle sibling", "Younger sibling" ].combination(2) do |roles|
        character.roles = roles
        assert_not character.valid?, "Expected conflicting family roles: #{roles.inspect}"
        assert_includes character.errors[:roles], "Choose only one family role."
      end
    end
  end

  test "hero villain and supporting are mutually exclusive" do
    character = characters(:hernandes)
    %w[Hero Villain Supporting].combination(2) do |roles|
      character.roles = roles
      assert_not character.valid?, "Expected conflicting story roles: #{roles.inspect}"
      assert_includes character.errors[:roles], "Choose only one story role."
    end
  end

  test "each family and story role can combine with all appearance traits" do
    character = characters(:hernandes)
    [ "Father", "Mother", "Big sibling", "Middle sibling", "Younger sibling" ].product(%w[Hero Villain Supporting]).each do |family, story|
      roles = [ family, "Piercings", "Tattoos", "Freckles", story ]
      character.update!(roles: roles)
      assert_equal roles, character.reload.roles
    end
  end

  test "character description is ready for image generation" do
    @character = characters(:hernandes)

    assert_equal("He is a 38 year old latino man with green eyes.\
 He has black hair color, and hair style is ponytail.",
         @character.generation_description)
  end


  test "characters cannot have the same name for the same user" do
    @one = characters(:hernandes)
    @two = Character.new(name: @one.name, user: @one.user, age: @one.age, gender: @one.gender, ethnicity: @one.ethnicity,
                          hair_color: @one.hair_color, hair_style: @one.hair_style, eye_color: @one.eye_color)

    assert_equal(@two.save, false)
    assert_equal(@two.errors.count, 1)
  end

  test "characters can have same name for different users" do
    @one = characters(:hernandes)
    @two = Character.new(name: @one.name, user: users(:two), age: @one.age, gender: @one.gender, ethnicity: @one.ethnicity,
                          hair_color: @one.hair_color, hair_style: @one.hair_style, eye_color: @one.eye_color)

    assert(@two.save)
    assert_equal(@two.errors.count, 0)
  end

  test "form creation requires all appearance fields" do
    character = Character.new(name: "Elara", user: users(:one), creation_mode: "form")

    assert_not character.valid?
    %i[age gender ethnicity hair_color hair_style eye_color].each do |attribute|
      assert_includes character.errors[attribute], "can't be blank"
    end
  end

  test "photo creation requires an uploaded photo" do
    character = Character.new(name: "Elara", user: users(:one), creation_mode: "photo")

    assert_not character.valid?
    assert_includes character.errors[:photo], "can't be blank"
  end

  test "uses gendered pronouns in image descriptions" do
    character = characters(:hernandes)
    character.gender = "Woman"

    assert_equal "she", character.pronoun_conversion
    assert_match(/^She is/, character.generation_description)
  end
end
