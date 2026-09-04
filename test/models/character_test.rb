# frozen_string_literal: true

require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  test "character description is ready for image generation" do
    @character = characters(:hernandes)

    assert_equal("He is a 38 year old latino man with green eyes.\
 He has black hair color, and hair style is ponytail. He also has the following traits: Caretaker.",
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
end
