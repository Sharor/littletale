module ApplicationHelper
  def omniauth_provider_configured?(provider)
    Devise.omniauth_configs.key?(provider)
  end

  def current_translations
    @translations ||= I18n.backend.send(:translations)
    @translations[I18n.locale].with_indifferent_access
  end

  def generation_failure_message(book)
    failure = book.generation_failure
    I18n.t("generation_failures.#{failure["type"]}", default: failure["message"])
  end

  def generation_provider_switch_reason(reason)
    if (match = reason.to_s.match(/\Aopenai_availability_failures_(\d+)_of_(\d+)\z/))
      return I18n.t("admin.generation_provider.switch_reasons.openai_availability_failures",
        failures: match[1], total: match[2])
    end

    I18n.t("admin.generation_provider.switch_reasons.#{reason}", default: reason.to_s.humanize)
  end
end
