# frozen_string_literal: true

require "test_helper"

class ChatgptTest < ActiveSupport::TestCase
  test "Instructions are clear" do
    @book = books(:one)
    @chatgpt = Chatgpt.new(book: @book)

    assert_nothing_raised { @chatgpt.storytellergpt_instructions }
  end

  test "Json input is valid" do
    @book = books(:one)
    @chatgpt = Chatgpt.new(book: @book)

    assert(JSON.parse(@chatgpt.input))
  end

  test "Json output is valid" do
    @book = books(:one)
    @chatgpt = Chatgpt.new(book: @book)

    assert(JSON.parse(@chatgpt.output))
  end
end
