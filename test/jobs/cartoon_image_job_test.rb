# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class CartoonImageJobTest < ActiveJob::TestCase
  self.fixture_table_names = []

  test "generates, broadcasts, and completes a photo-based character" do
    character_id = 73
    character = Minitest::Mock.new
    character.expect :update!, true, [], generation_status: :in_progress
    character.expect :id, character_id
    character.expect :id, character_id
    character.expect :completed!, true

    illustration = Minitest::Mock.new
    illustration.expect :cartoonify, true do |characters|
      assert_equal [ character.__id__ ], characters.map(&:__id__)
    end
    relation = Minitest::Mock.new
    relation.expect :first_or_initialize, illustration

    Character.stub :find, ->(id) { assert_equal character_id, id; character } do
      Illustration.stub :where, ->(scope) {
        assert_equal({ character_id: character_id }, scope)
        relation
      } do
        Turbo::StreamsChannel.stub :broadcast_replace_to, ->(stream, target:, partial:, locals:) {
          assert_equal "character_#{character_id}_updates", stream
          assert_equal "illustration_section_#{character_id}", target
          assert_equal "illustrations/illustration", partial
          assert_equal character.__id__, locals.fetch(:character).__id__
        } do
          CartoonImageJob.perform_now(character_id, "frontend-character-id")
        end
      end
    end

    character.verify
    illustration.verify
    relation.verify
  end
end
