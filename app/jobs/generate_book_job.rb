class GenerateBookJob < ApplicationJob
  queue_as :default

  def perform(book_id, generation_attempt = nil)
    Rails.logger.info("Generating Chatgpt for Book: #{book_id}")
    book = Book.find(book_id)
    generation_attempt ||= book.generation_attempt
    return unless book.generation_attempt == generation_attempt
    existing_plan = book.current_wardrobe_plan
    return unless (existing_plan && existing_plan.status != "pending") || book.ensure_character_images_ready!

    plan = book.with_lock do
      return unless book.generation_attempt == generation_attempt
      book.update!(generation_status: :in_progress) if book.pending?
      book.book_wardrobe_plans.find_or_create_by!(generation_attempt: generation_attempt)
    end
    BookWardrobePreparation.call(plan)
  end

  def initialize_AI(book)
    chatgpt = Chatgpt.new(book: book, prompt: book.plot)
    chatgpt.generate_v2
    chatgpt.save
  end

  def image_generation(story, book, generation_attempt = book.generation_attempt)
    story.each do |page_data|
      GeneratePageJob.perform_later(book.id, page_data, generation_attempt)
      # book.create_pages_from_answer(page) most likely deletable
    end
  end

  def ensure_storage_cache_consistency(book, max_retries = 5)
    attempts = 0
    until book.pages.all? { |p| p.illustration&.original_image&.present? } || attempts >= max_retries
      sleep 1 # Wait 1 second for disk/cloud consistency, especially s3
      book.pages.reload
      attempts += 1
    end
  end

  def broadcast_changes_swap_loadscreen(book, max_retries = 5)
    if book.pages.all? { |p| p.illustration&.original_image&.present? }
      book.completed!
      book.broadcast_replace_to(
        book,
        target: ActionView::RecordIdentifier.dom_id(book, :state),
        partial: "books/book_state",
        locals: { book: book }
      )
    else
      Rails.logger.error "Book #{book.id} failed to verify images after #{max_retries} seconds."
    end
  end
end
