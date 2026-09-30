# frozen_string_literal: true

module Lulu
  class Configuration
    SANDBOX_BASE_URL = "https://api.sandbox.lulu.com".freeze

    def self.enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("LULU_ORDERS_ENABLED", false))
    end

    def self.base_url
      SANDBOX_BASE_URL
    end
  end
end
