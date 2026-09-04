class ActionLog < ApplicationRecord
  belongs_to :trackable, polymorphic: true
  belongs_to :user

  scope :for_action, ->(name) { where(action: name) }
end
