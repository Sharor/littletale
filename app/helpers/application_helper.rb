module ApplicationHelper
  def current_translations
    @translations ||= I18n.backend.send(:translations)
    @translations[I18n.locale].with_indifferent_access
  end

  def generation_failure_message(book)
    failure = book.generation_failure
    I18n.t("generation_failures.#{failure["type"]}", default: failure["message"])
  end
end
