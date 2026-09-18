# frozen_string_literal: true

module Payments
  class Config
    class << self
      def account_id
        Rails.application.credentials.dig(:stripe, :account)
      end

      def webhook_secret
        Rails.application.credentials.dig(:stripe, :webhook_secret)
      end
    end
  end
end
