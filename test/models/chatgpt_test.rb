# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ChatgptTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(user: users(:one), name: "The lantern", plot: "A forest adventure", total_pages: 3)
    @book.characters << characters(:hernandes)
    @chatgpt = Chatgpt.new(book: @book, prompt: @book.plot)
  end

  test "provides storyteller instructions" do
    assert_includes @chatgpt.storytellergpt_instructions, "must always be valid JSON"
  end

  test "builds a prompt from the book's character, plot, and default audience" do
    messages = @chatgpt.chat_prompt_instruction(3)

    assert_equal 4, messages.size
    assert_includes messages.last[:content], "1 character(s)"
    assert_includes messages.last[:content], "Mr. Hernandes"
    assert_includes messages.last[:content], "A forest adventure"
    assert_includes messages.last[:content], "10 year old child"
    assert_includes messages.first[:content], "3 sections"
  end

  test "formats an adult audience without changing the stored value" do
    @chatgpt.audience = 21

    assert_equal "21 year old adult", @chatgpt.setup_target_audience
    assert_equal 21, @chatgpt.audience
  end

  test "serializes the book's total page count for structured generation" do
    input = JSON.parse(@chatgpt.jsonify)

    assert_equal 3, input.fetch("page_count")
    assert_equal "A forest adventure", input.fetch("plot")
  end

  test "structured generation specifies the book language and reader age" do
    @book.update!(language: "da", reader_age: 7)

    input = JSON.parse(@chatgpt.jsonify)
    instructions = @chatgpt.storytellergpt_instructions

    assert_equal "Danish", input.fetch("language")
    assert_equal 7, input.fetch("reader_age")
    assert_includes instructions, 'Write every "story" value in the requested language'
    assert_includes instructions, 'Keep every "image" value in English'
    assert_includes instructions, "reader_age"
  end

  test "structured generation identifies Greek as the book language" do
    @book.update!(language: "el")

    input = JSON.parse(@chatgpt.jsonify)

    assert_equal "Greek", input.fetch("language")
  end

  test "structured generation tells image descriptions to use the saved art style" do
    @book.update_column(:art_style, "claymation_plasticine")

    input = JSON.parse(@chatgpt.jsonify)
    instructions = @chatgpt.storytellergpt_instructions

    assert_includes input.fetch("art_style"), "plasticine"
    assert_includes input.fetch("art_style"), "stop-motion"
    assert_includes instructions, '"art_style"'
    assert_includes instructions, '"image"'
  end

  test "structured story input carries character metadata without account or image request fields" do
    character = characters(:hernandes)
    character.update!(roles: [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ])
    input = JSON.parse(@chatgpt.prompt_structured.last.fetch(:content))

    assert_equal({ "id" => character.id, "name" => "Mr. Hernandes", "age" => 38, "gender" => "Man",
      "ethnicity" => "Latino", "hair_color" => "Black", "hair_style" => "Ponytail", "eye_color" => "Green",
      "roles" => [ "Father", "Piercings", "Tattoos", "Freckles", "Villain" ] }, input.fetch("characters").sole)
    instructions = @chatgpt.prompt_structured.first.fetch(:content)
    assert_includes instructions, "family roles"
    assert_includes instructions, "Hero, Villain and Supporting"
    assert_includes instructions, "appearance, not morality"
  end

  test "structured story examples use optional lists from the role catalog" do
    [ @chatgpt.input, @chatgpt.example_input ].each do |example|
      JSON.parse(example).fetch("characters").each do |character|
        assert_kind_of Array, character["roles"]
        assert_empty character.fetch("roles") - Character::ROLES
        assert_not character.key?("role")
      end
    end
  end

  test "stores a mocked chat completion without making an external request" do
    completion = Struct.new(:choices).new([ Struct.new(:message).new(Struct.new(:content).new("A generated story")) ])
    completions = Minitest::Mock.new
    completions.expect :create, completion do |parameters|
      parameters[:model] == "gpt-3.5-turbo" && parameters[:messages].is_a?(Array)
    end
    chat = Struct.new(:completions).new(completions)
    client = Struct.new(:chat).new(chat)

    @chatgpt.stub :openai_client, client do
      assert @chatgpt.generate
    end

    assert_equal "A generated story", @chatgpt.answer
    completions.verify
  end

  test "does not request a completion when an answer already exists" do
    @chatgpt.answer = "Already generated"

    @chatgpt.stub :openai_client, -> { flunk "OpenAI should not be called" } do
      assert_nil @chatgpt.generate
    end
  end

  test "stores a mocked structured completion without making an external request" do
    client = Minitest::Mock.new
    client.expect :chat, { "choices" => [ { "message" => { "content" => "A structured story" } } ] } do |parameters|
      request = parameters.fetch(:parameters)
      request[:model] == "gpt-4.1" && request[:messages].last[:content].include?("page_count")
    end

    @chatgpt.stub :openai_client, client do
      @chatgpt.generate_v2
    end

    assert_equal "A structured story", @chatgpt.answer
    client.verify
  end

  test "bundled structured examples are valid JSON" do
    assert JSON.parse(@chatgpt.input)
    assert JSON.parse(@chatgpt.output)
    assert JSON.parse(@chatgpt.example_input)
    assert JSON.parse(@chatgpt.example_output)
  end
end
