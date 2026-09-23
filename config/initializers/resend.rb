# frozen_string_literal: true

resend_api_key = Rails.application.credentials.dig(:smtp, :resend_api_key)
Resend.api_key = resend_api_key if resend_api_key.present?
