# frozen_string_literal: true

class GenerationProviderRequest < ApplicationRecord
  PROVIDERS = GenerationProviderSetting::PROVIDERS
  OUTCOMES = %w[
    succeeded
    availability_failure
    content_rejected
    invalid_response
    configuration_error
    request_error
  ].freeze
  ELIGIBLE_OUTCOMES = %w[succeeded availability_failure].freeze

  validates :provider, inclusion: { in: PROVIDERS }
  validates :operation, :model, :started_at, :finished_at, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :http_status, numericality: { only_integer: true }, allow_nil: true
  validate :finished_after_started

  before_update { throw(:abort) }
  before_destroy { throw(:abort) }

  def self.record!(**attributes)
    request = create!(attributes)
    GenerationProviderSetting.current.evaluate_automatic_switch! if
      request.provider == "openai" && ELIGIBLE_OUTCOMES.include?(request.outcome)
    request
  end

  private

  def finished_after_started
    return unless started_at && finished_at && finished_at < started_at

    errors.add(:finished_at, "must be on or after the start time")
  end
end
