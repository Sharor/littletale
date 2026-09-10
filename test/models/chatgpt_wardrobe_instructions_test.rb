require "test_helper"
require "minitest/mock"

class ChatgptWardrobeInstructionsTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "structured storytelling requests clothing continuity while honoring mixed activities" do
    chatgpt = Chatgpt.new
    chatgpt.stub :jsonify, '{"plot":"Biking then swimming"}' do
      instructions = chatgpt.prompt_structured.first.fetch(:content)
      assert_includes instructions, "one outfit per character"
      assert_includes instructions, "explicitly requested activities"
      assert_includes instructions, "natural clothing transition"
      assert_includes instructions, "age-appropriate swimwear"
      assert_includes instructions, "must always be valid JSON"
    end
  end
end
