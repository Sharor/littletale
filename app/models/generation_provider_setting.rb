# frozen_string_literal: true

class GenerationProviderSetting < ApplicationRecord
  SINGLETON_KEY = "global"
  MODES = %w[openai gemini automatic].freeze
  PROVIDERS = %w[openai gemini].freeze
  WINDOW_SIZE = 20
  FAILURE_THRESHOLD = 16

  validates :key, inclusion: { in: [ SINGLETON_KEY ] }, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :active_provider, inclusion: { in: PROVIDERS }

  def self.current
    find_or_create_by!(key: SINGLETON_KEY)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def provider
    mode == "automatic" ? active_provider : mode
  end

  def change_mode!(new_mode)
    raise ArgumentError, "Unknown generation provider mode" unless MODES.include?(new_mode)

    with_lock do
      now = Time.current
      if new_mode == "automatic"
        update!(
          mode: new_mode,
          active_provider: "openai",
          automatic_window_started_at: now,
          switched_at: nil,
          switch_reason: "automatic_enabled"
        )
      else
        update!(
          mode: new_mode,
          active_provider: new_mode,
          automatic_window_started_at: nil,
          switched_at: now,
          switch_reason: "admin_selected_#{new_mode}"
        )
      end
    end
    self
  end

  def eligible_openai_window
    return GenerationProviderRequest.none.to_a unless automatic_window_started_at

    GenerationProviderRequest
      .where(provider: "openai", outcome: GenerationProviderRequest::ELIGIBLE_OUTCOMES)
      .where(started_at: automatic_window_started_at..)
      .order(finished_at: :desc, id: :desc)
      .limit(WINDOW_SIZE)
      .to_a
  end

  def evaluate_automatic_switch!
    with_lock do
      return provider unless mode == "automatic" && active_provider == "openai"

      window = eligible_openai_window
      return provider if window.length < WINDOW_SIZE

      failures = window.count { |request| request.outcome == "availability_failure" }
      if failures >= FAILURE_THRESHOLD
        update!(
          active_provider: "gemini",
          switched_at: Time.current,
          switch_reason: "openai_availability_failures_#{failures}_of_#{WINDOW_SIZE}"
        )
      end
      provider
    end
  end
end
