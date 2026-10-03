# frozen_string_literal: true

require "test_helper"

class Admin::GenerationProvidersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    GenerationProviderRequest.delete_all
    GenerationProviderSetting.delete_all
  end

  test "an administrator can select OpenAI Gemini and Automatic when credentials are configured" do
    sign_in admin

    with_env("OPENAI_ACCESS_TOKEN" => "openai-key", "GEMINI_API_KEY" => "gemini-key") do
      %w[openai gemini automatic].each do |mode|
        patch admin_generation_provider_path, params: { mode: mode }

        assert_redirected_to admin_root_path
        setting = GenerationProviderSetting.current.reload
        assert_equal mode, setting.mode
        assert_equal(mode == "gemini" ? "gemini" : "openai", setting.active_provider)
      end
    end
  end

  test "missing credentials reject a mode change without changing routing" do
    sign_in admin
    setting = GenerationProviderSetting.current

    with_env("OPENAI_ACCESS_TOKEN" => "openai-key", "GEMINI_API_KEY" => nil) do
      patch admin_generation_provider_path, params: { mode: "gemini" }
    end

    assert_redirected_to admin_root_path
    assert_equal "openai", setting.reload.mode
    assert_equal "Gemini is not configured. Add GEMINI_API_KEY before selecting this mode.", flash[:alert]

    with_env("OPENAI_ACCESS_TOKEN" => nil, "GEMINI_API_KEY" => "gemini-key") do
      patch admin_generation_provider_path, params: { mode: "automatic" }
    end

    assert_redirected_to admin_root_path
    assert_equal "openai", setting.reload.mode
    assert_equal "OpenAI is not configured. Add OPENAI_ACCESS_TOKEN before selecting this mode.", flash[:alert]
  end

  test "unknown modes are rejected without changing routing" do
    sign_in admin
    setting = GenerationProviderSetting.current

    with_env("OPENAI_ACCESS_TOKEN" => "openai-key", "GEMINI_API_KEY" => "gemini-key") do
      patch admin_generation_provider_path, params: { mode: "other" }
    end

    assert_redirected_to admin_root_path
    assert_equal "openai", setting.reload.mode
    assert_equal "Choose a valid generation provider mode.", flash[:alert]
  end

  test "non-admins cannot change generation routing" do
    setting = GenerationProviderSetting.current

    patch admin_generation_provider_path, params: { mode: "gemini" }
    assert_response :forbidden

    sign_in users(:one)
    with_env("GEMINI_API_KEY" => "gemini-key") do
      patch admin_generation_provider_path, params: { mode: "gemini" }
    end
    assert_response :forbidden
    assert_equal "openai", setting.reload.mode
  end

  private

  def admin
    users(:three).tap { |user| user.update!(admin: true) }
  end

  def with_env(values)
    original = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
