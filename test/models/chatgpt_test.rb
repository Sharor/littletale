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
