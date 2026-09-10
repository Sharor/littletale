class GeneratePageJob < ApplicationJob
  queue_as :default

  def perform(book_id, page_data, generation_attempt = nil)
    book = Book.find(book_id)
    generation_attempt ||= book.generation_attempt
    return unless book.generation_attempt == generation_attempt
    return unless page_data["wardrobe_plan_id"] || book.ensure_character_images_ready!

    book.create_pages_from_answer(page_data, attempt: generation_attempt)
    book.refresh_generation_status!(attempt: generation_attempt)
  end
end
