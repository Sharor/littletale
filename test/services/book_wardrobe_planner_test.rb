# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BookWardrobePlannerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @character = Character.new(id: 42, name: "Mia", age: 7, gender: "Girl", ethnicity: "Asian",
      hair_color: "Brown", hair_style: "Braids", eye_color: "Green", roles: ["Hero"])
    @book = Struct.new(:plot, :characters).new("Ride bikes then swim", [@character])
    @story = [{ "story" => "Mia rode her bike.", "image" => "Mia cycling" },
      { "story" => "Mia changed and swam.", "image" => "Mia swimming" }]
  end

  test "plans from complete story and character snapshots using structured JSON" do
    plan = { "outfits" => [
      { "character_id" => 42, "key" => "cycling", "description" => "Yellow shirt, blue shorts, helmet", "pages" => [1] },
      { "character_id" => 42, "key" => "swimming", "description" => "Blue swimwear", "pages" => [2] }
    ] }
    captured = nil
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      captured = parameters
      { "choices" => [{ "message" => { "content" => plan.to_json } }] }
    end

    OpenAI::Client.stub :new, client do
      assert_equal plan, BookWardrobePlanner.call(@book, @story)
    end

    assert_equal "gpt-4.1", captured[:model]
    assert_equal({ type: "json_object" }, captured[:response_format])
    assert_equal "system", captured[:messages].first[:role]
    context = JSON.parse(captured[:messages].last[:content])
    assert_equal @book.plot, context.fetch("plot")
    assert_equal @story, context.fetch("story")
    assert_equal 2, context.fetch("page_count")
    snapshot = context.fetch("characters").sole
    assert_equal 42, snapshot.fetch("id")
    assert_equal "Mia", snapshot.fetch("name")
    assert_equal 7, snapshot.fetch("age")
    assert_equal "Girl", snapshot.fetch("gender")
    assert_equal "Asian", snapshot.fetch("ethnicity")
    assert_equal "Brown", snapshot.fetch("hair_color")
    assert_equal "Braids", snapshot.fetch("hair_style")
    assert_equal "Green", snapshot.fetch("eye_color")
    assert_equal ["Hero"], snapshot.fetch("roles")
  end

  test "rejects refused missing malformed and non-object responses without retries" do
    [ { "refusal" => "Cannot comply", "content" => '{"outfits":[]}' }, {},
      { "content" => " " }, { "content" => "not JSON" }, { "content" => "[]" },
      { "content" => "null" } ].each do |message|
      calls = 0
      client = Object.new
      client.define_singleton_method(:chat) do |parameters:|
        calls += 1
        { "choices" => [{ "message" => message }] }
      end
      OpenAI::Client.stub :new, client do
        assert_raises(BookWardrobePlanner::Error) { BookWardrobePlanner.call(@book, @story) }
      end
      assert_equal 1, calls
    end
  end
end
