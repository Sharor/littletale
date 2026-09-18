# frozen_string_literal: true

class StripeEvent < ApplicationRecord
  validates :stripe_event_id, :event_type, :processed_at, presence: true
end
