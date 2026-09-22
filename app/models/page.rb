class Page < ApplicationRecord
  belongs_to :book, touch: true
  belongs_to :book_wardrobe_plan, optional: true

  def wardrobe_required?
    book_wardrobe_plan_id.present?
  end

  def book_outfits
    return [] unless wardrobe_required?
    book_wardrobe_plan.book_outfits.order(:character_id).select { |outfit| outfit.page_numbers.include?(story_position) }
  end

  def wardrobe_ready?
    return true unless wardrobe_required?
    book_wardrobe_plan.ready? && book_outfits.length == book_wardrobe_plan.character_snapshots.length &&
      book_outfits.all? { |outfit| outfit.status == "ready" && outfit.image.attached? }
  end

  def wardrobe_instructions
    return "" unless wardrobe_required?
    "Use the saved book outfits below exactly, overriding conflicting clothing in the scene description. " \
      "Preserve character identity and age. Keep clothing items, colors, footwear and equipment consistent; " \
      "depict only characters present in this scene. Saved outfits: " +
      book_outfits.map { |outfit| { character: outfit.character_snapshot, outfit: outfit.description } }.to_json
  end

  # Broadcast specifically to the book's stream, replacing only the castle
  after_create_commit -> {
    I18n.with_locale(book.user.language.presence_in(User::SUPPORTED_LANGUAGES.keys) || I18n.default_locale) do
      broadcast_replace_to book,
      target: "castle_construction",
      partial: "books/castle",
      locals: { book: book }
    end
  }

  has_one :illustration, dependent: :destroy
end
