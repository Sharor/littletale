# frozen_string_literal: true

class BookCategory
  CATALOG_PATH = Rails.root.join("categories.md")

  class << self
    def all
      @all ||= CATALOG_PATH.readlines(chomp: true).map(&:strip).reject(&:blank?).uniq.freeze
    end

    def include?(category)
      all.include?(category)
    end
  end
end
