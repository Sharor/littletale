# frozen_string_literal: true

class Admin::GenerationProvidersController < ApplicationController
  skip_before_action :check_tutorial
  before_action -> { head :forbidden unless current_user&.admin? }

  def update
    mode = params[:mode].to_s
    unless GenerationProviderSetting::MODES.include?(mode)
      return redirect_to admin_root_path, alert: I18n.t("admin.generation_provider.invalid_mode")
    end

    missing = missing_credential(mode)
    if missing
      return redirect_to admin_root_path, alert: I18n.t("admin.generation_provider.missing_#{missing}")
    end

    unavailable = unavailable_provider(mode)
    if unavailable
      return redirect_to admin_root_path, alert: I18n.t("admin.generation_provider.unavailable_#{unavailable}")
    end

    GenerationProviderSetting.current.change_mode!(mode)
    redirect_to admin_root_path,
      notice: I18n.t("admin.generation_provider.updated", mode: I18n.t("admin.generation_provider.modes.#{mode}.title"))
  end

  private

  def missing_credential(mode)
    return "openai" if %w[openai automatic].include?(mode) && ENV["OPENAI_ACCESS_TOKEN"].blank?
    "gemini" if %w[gemini automatic].include?(mode) && ENV["GEMINI_API_KEY"].blank?
  end

  def unavailable_provider(mode)
    required_providers(mode).find do |provider|
      check = provider == "openai" ? HealthChecks::Openai.new : HealthChecks::Gemini.new
      check.call.status != "connected"
    end
  end

  def required_providers(mode)
    case mode
    when "automatic" then %w[openai gemini]
    else [ mode ]
    end
  end
end
