class Page < ApplicationRecord
  belongs_to :book, touch: true

  # Broadcast specifically to the book's stream, replacing only the castle
  after_create_commit -> {
    broadcast_replace_to book,
    target: "castle_construction",
    partial: "books/castle",
    locals: { book: book }
  }

  has_one :illustration, dependent: :destroy
end
