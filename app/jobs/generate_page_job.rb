class GeneratePageJob < ApplicationJob
  queue_as :default

  def perform(book_id, page_data)
    book = Book.find(book_id)
    book.create_pages_from_answer(page_data)
  end
end
