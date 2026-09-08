class CharacterImageGenerationAttempt < ApplicationRecord
  belongs_to :request, class_name: "CharacterImageRequest"
  belongs_to :action_log
  belongs_to :illustration, optional: true
  has_one_attached :result_image
  validates :status, inclusion: { in: %w[reserved in_progress completed failed outcome_unknown] }
end
