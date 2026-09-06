require "test_helper"
require "minitest/mock"

class GenerateImageJobTest < ActiveJob::TestCase
  self.fixture_table_names = []

  test "marks the character as complete after generating its illustration" do
    character_id = 42
    description = "A friendly wizard with a blue hat"

    character = Minitest::Mock.new
    character.expect :in_progress!, true
    character.expect :completed!, true

    illustration = Minitest::Mock.new
    illustration.expect :generate_single_character, true, [ description ]

    relation = Minitest::Mock.new
    relation.expect :first_or_initialize, illustration

    Character.stub :find, ->(id) { assert_equal character_id, id; character } do
      Illustration.stub :where, ->(scope) {
        assert_equal({ character_id: character_id }, scope)
        relation
      } do
        GenerateImageJob.perform_now(character_id, description)
      end
    end

    character.verify
    illustration.verify
    relation.verify
  end
end
