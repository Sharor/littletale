class CharacterImageDecision < ApplicationRecord
  belongs_to :user
  belongs_to :assessment, class_name: "CharacterImageAssessment"
  belongs_to :request, class_name: "CharacterImageRequest", optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  validates :outcome, inclusion: { in: %w[approved needs_review rejected] }
  validates :source, inclusion: { in: %w[automatic admin provider] }
  scope :for_outcome, ->(outcome) { where(outcome: outcome) }

  def readonly?
    persisted?
  end
end
