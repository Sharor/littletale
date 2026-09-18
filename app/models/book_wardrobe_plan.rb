# frozen_string_literal: true

class BookWardrobePlan < ApplicationRecord
  class InvalidPlan < StandardError; end

  belongs_to :book
  has_many :book_outfits, dependent: :destroy
  has_many :pages, dependent: :nullify
  has_many_attached :source_images
  validates :generation_attempt, uniqueness: { scope: :book_id }
  validates :status, inclusion: { in: %w[pending planning preparing ready failed] }

  def current?
    generation_attempt == book.reload.generation_attempt
  end

  def ready?
    status == "ready"
  end

  def validate_story!(value)
    unless value.is_a?(Array) && value.length == book.total_pages && value.all? { |page| page.is_a?(Hash) && page["story"].is_a?(String) && page["story"].present? && page["image"].is_a?(String) && page["image"].present? }
      raise InvalidPlan, "The story must contain the requested number of complete pages"
    end
    true
  end

  def validate_outfits!(value)
    outfits = value.is_a?(Hash) && value["outfits"]
    raise InvalidPlan, "The wardrobe must contain outfits" unless outfits.is_a?(Array)

    ids = character_snapshots.present? ? character_snapshots.map { |character| character.fetch("id") } : book.characters.pluck(:id)
    assignments = Hash.new { |hash, key| hash[key] = [] }
    keys = []
    outfits.each do |outfit|
      unless outfit.is_a?(Hash) && ids.include?(outfit["character_id"]) && outfit["key"].is_a?(String) && outfit["key"].match?(/\A[a-zA-Z0-9_-]{1,80}\z/) && outfit["description"].is_a?(String) && outfit["description"].present? && outfit["description"].length <= 4000 && outfit["pages"].is_a?(Array) && outfit["pages"].present? && outfit["pages"].all? { |number| number.is_a?(Integer) && number.between?(1, story.length) }
        raise InvalidPlan, "Invalid wardrobe assignment"
      end
      key = [outfit["character_id"], outfit["key"]]
      raise InvalidPlan, "Duplicate outfit" if keys.include?(key)
      keys << key
      assignments[outfit["character_id"]].concat(outfit["pages"])
    end
    ids.each do |id|
      raise InvalidPlan, "Every character needs exactly one outfit per page" unless assignments[id].sort == (1..story.length).to_a
    end
    true
  end

  def fail!(type:, message:, metadata: {})
    evidence = book.generation_failure_context(
      "type" => type, "message" => message, "wardrobe_plan_id" => id, "metadata" => metadata
    )
    update!(status: "failed", failure: evidence)
    book.with_lock do
      return unless book.generation_attempt == generation_attempt
      book.update!(generation_status: :failed, generation_failed_at: Time.current,
        generation_failure: evidence, generation_failure_history: book.generation_failure_history + [evidence])
    end
    book.send(:broadcast_generation_state)
  end
end
