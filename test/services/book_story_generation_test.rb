# frozen_string_literal: true

require "test_helper"

class BookStoryGenerationTest < ActiveSupport::TestCase
  FakeChat = Struct.new(:messages, :openai_client, :answer, keyword_init: true) do
    def prompt_structured = messages
    def save! = true
  end

  test "snapshot story generation carries the saved art style" do
    book = Book.create!(user: users(:one), name: "Paper forest", plot: "A forest walk", total_pages: 1,
      art_style: "cut_paper_collage")
    received = nil
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      received = parameters
      { "choices" => [ { "message" => { "content" => [ { story: "A walk.", image: "A forest." } ].to_json } } ] }
    end
    chat = FakeChat.new(messages: [ { role: "developer", content: "instructions" }, { role: "user", content: "{}" } ],
      openai_client: client)

    Chatgpt.stub :new, chat do
      BookStoryGeneration.call(book, character_snapshots: [])
    end

    input = JSON.parse(received.fetch(:messages).last.fetch(:content))
    assert_includes input.fetch("art_style"), "Cut-paper collage"
    assert_includes input.fetch("art_style"), "tactile fibers"
  end
end
