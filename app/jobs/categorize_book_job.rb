# frozen_string_literal: true

class CategorizeBookJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(book_id, generation_attempt)
    book = Book.find(book_id)
    return unless book.completed? && book.generation_attempt == generation_attempt
    return if book.categories.present?

    BookCategorization.call(book, generation_attempt: generation_attempt)
  end

  def self.enqueue_missing
    Book.completed.where(categorization_enqueued_at: nil).where("json_array_length(categories) = 0").find_each do |book|
      book.enqueue_categorization!
    end
  end
end
