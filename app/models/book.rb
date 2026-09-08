class Book < ApplicationRecord
  enum :generation_status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }
  belongs_to :user

  has_one :chatgpt
  has_and_belongs_to_many :characters
  has_many :pages
  has_many :illustrations, through: :pages

  validates :name, presence: true

  broadcasts_to ->(book) { book }, inserts_by: :replace

  # after_update_commit -> {
  #   broadcast_replace_later_to self,
  #     target: ActionView::RecordIdentifier.dom_id(self, :state),
  #     partial: "books/book_state",
  #     locals: { book: self }
  # }

  validates :total_pages, presence: true, numericality: { greater_than: 0 }
  validate :total_pages_within_tier_limit

  TIER_LIMITS = {
    "free"       => 5,
    "basic"      => 10,
    "adventurer" => 15,
    "premium"    => 20
  }.freeze

  def tier_limit
    TIER_LIMITS.fetch(user.tier, 5)
  end

  def total_pages_within_tier_limit
    return unless total_pages.present?

    if total_pages > tier_limit
      errors.add(:total_pages, "cannot exceed #{tier_limit} pages for the #{user.tier.capitalize} tier")
    end
  end

  # For frontend purposes
  def construction_level
    return 0 if total_pages.to_i.zero?

    percent = (current_pages.count.to_f / total_pages * 100).round
    case percent
    when 0..19   then 1 # Foundation
    when 20..39  then 2 # Walls
    when 40..59  then 3 # Towers
    when 60..79  then 4 # Roofs
    when 80..94  then 5 # Flag Raised
    else              6 # Magical Glow (100%)
    end
  end

  # Generation logic

  def characters_ready_for_generation?
    characters.all? { |character| character.user_id == user_id && character.image_ready_for_book? }
  end

  def ensure_character_images_ready!
    return true if characters_ready_for_generation?

    update_columns(generation_status: self.class.generation_statuses.fetch("failed"),
      generation_failed_at: Time.current,
      generation_failure: { "type" => "character_image_not_ready",
        "message" => "One or more selected character images are not ready. Choose ready characters before starting this book." })
    broadcast_generation_state
    false
  end

  def write_storyline
    Rails.logger.error("Chatpgt id:#{chatgpt.id} had no answer for book.rb.") && return if chatgpt.answer.blank?

    JSON.parse(chatgpt.answer)
  end

  def current_pages
    pages.where(generation_attempt: generation_attempt)
  end

  def create_pages_from_answer(json, attempt: generation_attempt)
    page = pages.create!(text: json["story"], generation_attempt: attempt)
    page.illustration = Illustration.create!(original_description: json["image"])
    # You need to finish this by doing a comparison of page["present"] and characters in Book. TODO maybe?
    page.illustration.generate_image_v1(characters)
    page
  end

  def record_generation_failure!(illustration:, failure:, request:)
    return unless illustration.page.generation_attempt == generation_attempt

    context = failure.merge(
      "book_id" => id,
      "page_id" => illustration.page_id,
      "illustration_id" => illustration.id,
      "generation_attempt" => generation_attempt,
      "request" => request,
      "book_context" => generation_context
    )

    update!(
      generation_status: :failed,
      generation_failed_at: Time.current,
      generation_failure: context,
      generation_failure_history: generation_failure_history + [ context ]
    )
    broadcast_generation_state
  end

  def refresh_generation_status!(attempt: generation_attempt)
    return unless attempt == generation_attempt
    return if failed?
    return unless current_pages.count >= total_pages
    return unless current_pages.all? { |page| page.illustration&.original_image&.present? }

    completed!
    broadcast_generation_state
  end

  def prepare_for_regeneration!
    with_lock do
      history = generation_failure_history
      history += [ generation_failure ] if generation_failure.present? && !history.include?(generation_failure)

      update!(
        generation_attempt: generation_attempt + 1,
        generation_status: :pending,
        generation_failure: {},
        generation_failed_at: nil,
        generation_failure_history: history
      )
      generation_attempt
    end
  end

  def finished_generation?
    current_pages.any? { |page| page&.illustration&.original_image&.present? }
  end

  def progress?
    current_pages.select { |page| page&.illustration&.original_image&.present? }.count
  end

  private

  def generation_context
    {
      "name" => name,
      "plot" => plot,
      "total_pages" => total_pages,
      "characters" => characters.map do |character|
        illustration = character.illustration
        {
          "id" => character.id,
          "name" => character.name,
          "age" => character.age,
          "gender" => character.gender,
          "illustration_id" => illustration&.id,
          "reference_image" => illustration&.original_image&.identifier
        }
      end,
      "chatgpt_id" => chatgpt&.id,
      "story_response" => chatgpt&.answer
    }
  end

  def broadcast_generation_state
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :state),
      partial: "books/book_state",
      locals: { book: self }
    )
  end
end
