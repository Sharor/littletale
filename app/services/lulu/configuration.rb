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

    def self.client_id
      Rails.application.credentials.dig(:lulu, :client)
    end

    def self.client_secret
      Rails.application.credentials.dig(:lulu, :secret)
    end

    def self.credentials_ready?
      client_id.present? && client_secret.present?
    end

    def self.asset_host
      ENV["LULU_ASSET_HOST"].to_s.delete_suffix("/")
    end

    def self.asset_host_ready?
      uri = URI.parse(asset_host)
      uri.scheme == "https" && uri.host.present? && !local_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def self.local_host?(host)
      normalized = host.to_s.downcase
      normalized == "localhost" || normalized == "::1" || normalized.start_with?("127.")
    end
    private_class_method :local_host?
  end
end
