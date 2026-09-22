# frozen_string_literal: true

class BookStoryGeneration
  def self.call(book, character_snapshots: nil)
    chat = Chatgpt.new(book: book, prompt: book.plot)
    messages = chat.prompt_structured
    if character_snapshots
      messages.last[:content] = { page_count: book.total_pages, characters: character_snapshots, plot: book.plot,
        language: User::GENERATION_LANGUAGE_NAMES.fetch(book.language, "English"), reader_age: book.reader_age,
        art_style: book.art_style_prompt }.to_json
    end
    response = chat.openai_client.chat(parameters: {
      messages: messages, model: "gpt-4.1", max_tokens: 8000, temperature: 0.7
    })
    message = response.dig("choices", 0, "message") || {}
    raise BookWardrobePlan::InvalidPlan, "Story generation refused" if message["refusal"].present?
    chat.answer = message["content"]
    story = JSON.parse(chat.answer.to_s)
    chat.save!
    story
  end
end
