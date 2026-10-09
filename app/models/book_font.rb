# frozen_string_literal: true

class BookFont
  Font = Data.define(:key, :name, :css_class, :pdf_family)
  DEFAULT_KEY = "eb_garamond"

  FONTS = [
    Font.new(key: "eb_garamond", name: "EB Garamond",
      css_class: "book-font-eb-garamond", pdf_family: "EB Garamond"),
    Font.new(key: "inter", name: "Inter",
      css_class: "book-font-inter", pdf_family: "Inter")
  ].freeze

  BY_KEY = FONTS.index_by(&:key).freeze

  class << self
    def all = FONTS
    def keys = BY_KEY.keys
    def fetch(key) = BY_KEY.fetch(key)
    def find(key) = BY_KEY[key]
    def default = fetch(DEFAULT_KEY)
  end
end
