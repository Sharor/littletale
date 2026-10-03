# frozen_string_literal: true

module GenerationProviders
  class Client
    def initialize(operation:, adapter_factory: ->(provider) { GenerationProviders.adapter_for(provider) })
      @operation = operation
      @adapter_factory = adapter_factory
    end

    def chat(parameters:)
      dispatch(:chat, parameters)
    end

    def moderations(parameters:)
      dispatch(:moderations, parameters)
    end

    def images
      self
    end

    def generate(parameters:)
      dispatch(:generate, parameters)
    end

    def edit(parameters:)
      dispatch(:edit, parameters)
    end

    private

    def dispatch(capability, parameters)
      provider = GenerationProviderSetting.current.provider
      adapter = @adapter_factory.call(provider)
      model = adapter.model_for(capability, parameters)
      started_at = Time.current
      response = nil
      error = nil
      outcome = nil

      begin
        response = adapter.public_send(capability, parameters: parameters)
        validate_response!(capability, response)
        outcome = "succeeded"
        response
      rescue StandardError => caught
        error = caught
        outcome = outcome_for(caught)
        raise
      ensure
        record_outcome(
          provider: provider,
          model: model,
          outcome: outcome,
          started_at: started_at,
          response: response,
          error: error
        ) if outcome
      end
    end

    def validate_response!(capability, response)
      valid = case capability
      when :chat
        message = response.is_a?(Hash) && response.dig("choices", 0, "message")
        message.is_a?(Hash) && (message.key?("content") || message["refusal"].present?)
      when :generate, :edit
        image = response.is_a?(Hash) && response.dig("data", 0)
        image.is_a?(Hash) && (image["b64_json"].is_a?(String) || image["url"].is_a?(String))
      when :moderations
        result = response.is_a?(Hash) && response.dig("results", 0)
        result.is_a?(Hash)
      end
      raise InvalidResponse, "The provider returned a malformed #{capability} response" unless valid
    end

    def outcome_for(error)
      return "content_rejected" if error.is_a?(ContentRejected)
      return "invalid_response" if error.is_a?(InvalidResponse)

      status = http_status(error)
      return "configuration_error" if [ 401, 403 ].include?(status)
      return "availability_failure" if availability_failure?(error, status)

      "request_error"
    end

    def availability_failure?(error, status)
      error.is_a?(Faraday::TimeoutError) || error.is_a?(Faraday::ConnectionFailed) ||
        status == 429 || status&.between?(500, 599)
    end

    def record_outcome(provider:, model:, outcome:, started_at:, response:, error:)
      GenerationProviderRequest.record!(
        provider: provider,
        operation: @operation,
        model: model,
        outcome: outcome,
        http_status: http_status(error),
        error_class: error&.class&.name,
        external_request_id: request_id(response, error),
        started_at: started_at,
        finished_at: Time.current
      )
    rescue StandardError => tracking_error
      Rails.logger.error("Generation provider tracking failed: #{tracking_error.class.name}")
    end

    def http_status(error)
      response = error.respond_to?(:response) ? error.response : nil
      status = response.is_a?(Hash) && (response[:status] || response["status"])
      Integer(status, exception: false)
    end

    def request_id(response, error)
      value = response["id"] || response["request_id"] if response.is_a?(Hash)
      if value.blank? && error.respond_to?(:response) && error.response.is_a?(Hash)
        headers = error.response[:headers] || error.response["headers"] || {}
        value = headers["x-request-id"] || headers["x-goog-request-id"]
      end
      sanitize_identifier(value)
    end

    def sanitize_identifier(value)
      return unless value.is_a?(String)

      value = value.strip
      value.first(255) if value.present? && value.match?(/\A[[:alnum:]_.:\/-]+\z/)
    end
  end
end
