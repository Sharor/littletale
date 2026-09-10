# frozen_string_literal: true

class BookOutfit < ApplicationRecord
  belongs_to :book_wardrobe_plan
  has_one_attached :source_image
  has_one_attached :image
  validates :outfit_key, uniqueness: { scope: [:book_wardrobe_plan_id, :character_id] }
  validates :description, presence: true
  validates :status, inclusion: { in: %w[pending generating ready rejected failed outcome_unknown] }
end
