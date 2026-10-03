# frozen_string_literal: true

require "test_helper"

class GenerationProviderSettingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    GenerationProviderRequest.delete_all if ActiveRecord::Base.connection.data_source_exists?("generation_provider_requests")
    GenerationProviderSetting.delete_all if ActiveRecord::Base.connection.data_source_exists?("generation_provider_settings")
  end

  teardown do
    GenerationProviderRequest.delete_all if ActiveRecord::Base.connection.data_source_exists?("generation_provider_requests")
    GenerationProviderSetting.delete_all if ActiveRecord::Base.connection.data_source_exists?("generation_provider_settings")
  end

  test "current lazily defaults to OpenAI" do
    setting = GenerationProviderSetting.current

    assert_equal "global", setting.key
    assert_equal "openai", setting.mode
    assert_equal "openai", setting.active_provider
    assert_equal "openai", setting.provider
    assert_equal 1, GenerationProviderSetting.count
  end

  test "manual modes route directly and clear the automatic window" do
    setting = GenerationProviderSetting.current
    setting.change_mode!("gemini")

    assert_equal "gemini", setting.reload.provider
    assert_nil setting.automatic_window_started_at
    assert_equal "admin_selected_gemini", setting.switch_reason

    setting.change_mode!("openai")

    assert_equal "openai", setting.reload.provider
    assert_nil setting.automatic_window_started_at
    assert_equal "admin_selected_openai", setting.switch_reason
  end

  test "automatic mode resets its observation window and begins on OpenAI" do
    setting = GenerationProviderSetting.current
    setting.change_mode!("gemini")
    before = Time.current

    setting.change_mode!("automatic")

    assert_equal "automatic", setting.reload.mode
    assert_equal "openai", setting.active_provider
    assert_equal "openai", setting.provider
    assert_operator setting.automatic_window_started_at, :>=, before
    assert_equal "automatic_enabled", setting.switch_reason
  end

  test "automatic mode waits for twenty eligible requests" do
    setting = automatic_setting

    16.times { record(outcome: "availability_failure") }

    assert_equal "openai", setting.reload.provider
    assert_equal 16, setting.eligible_openai_window.length
  end

  test "fifteen failures in the latest twenty do not switch" do
    setting = automatic_setting

    15.times { record(outcome: "availability_failure") }
    5.times { record(outcome: "succeeded") }

    assert_equal "openai", setting.reload.provider
    assert_nil setting.switched_at
  end

  test "sixteen failures in the latest twenty switch future requests to Gemini" do
    setting = automatic_setting

    16.times { record(outcome: "availability_failure") }
    4.times { record(outcome: "succeeded") }

    assert_equal "gemini", setting.reload.provider
    assert_equal "openai_availability_failures_16_of_20", setting.switch_reason
    assert_not_nil setting.switched_at
  end

  test "non-availability outcomes do not enter the automatic window" do
    setting = automatic_setting
    %w[content_rejected invalid_response configuration_error request_error].each do |outcome|
      5.times { record(outcome: outcome) }
    end
    15.times { record(outcome: "availability_failure") }
    5.times { record(outcome: "succeeded") }

    assert_equal "openai", setting.reload.provider
    assert_equal 20, setting.eligible_openai_window.length
  end

  test "requests started before automatic mode are excluded even if they finish later" do
    setting = GenerationProviderSetting.current
    started_at = 1.minute.ago
    setting.change_mode!("automatic")

    20.times { record(outcome: "availability_failure", started_at: started_at) }

    assert_equal "openai", setting.reload.provider
    assert_empty setting.eligible_openai_window
  end

  test "automatic mode does not return to OpenAI after switching" do
    setting = automatic_setting
    16.times { record(outcome: "availability_failure") }
    4.times { record(outcome: "succeeded") }
    assert_equal "gemini", setting.reload.provider

    20.times { record(outcome: "succeeded") }

    assert_equal "gemini", setting.reload.provider
    assert_equal "openai_availability_failures_16_of_20", setting.switch_reason
  end

  test "concurrent threshold evaluation leaves one stable singleton switch" do
    setting = automatic_setting
    started_at = setting.automatic_window_started_at + 1.second
    rows = 16.times.map { request_attributes(outcome: "availability_failure", started_at: started_at) } +
      4.times.map { request_attributes(outcome: "succeeded", started_at: started_at) }
    GenerationProviderRequest.insert_all!(rows)

    errors = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          GenerationProviderSetting.current.evaluate_automatic_switch!
        rescue StandardError => error
          errors << error
        end
      end
    end
    threads.each(&:join)

    assert_empty errors
    assert_equal 1, GenerationProviderSetting.count
    assert_equal "gemini", setting.reload.provider
    assert_equal "openai_availability_failures_16_of_20", setting.switch_reason
  end

  private

  def automatic_setting
    GenerationProviderSetting.current.tap { |setting| setting.change_mode!("automatic") }
  end

  def record(outcome:, started_at: Time.current)
    GenerationProviderRequest.record!(
      provider: "openai",
      operation: "test_generation",
      model: "test-model",
      outcome: outcome,
      started_at: started_at,
      finished_at: Time.current
    )
  end

  def request_attributes(outcome:, started_at:)
    {
      provider: "openai",
      operation: "test_generation",
      model: "test-model",
      outcome: outcome,
      started_at: started_at,
      finished_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end
