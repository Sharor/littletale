# frozen_string_literal: true

class BookWardrobeFailure
  QUOTA_CODES = %w[insufficient_quota credit_balance_exhausted organization_usage_limit_exceeded organization_spend_limit_exceeded project_spend_limit_exceeded].freeze
  QUOTA_MESSAGE = "Book generation is unavailable because the AI provider's credit or usage limit has been reached. Please contact support."

  def self.details(error, stage:)
    response = error.respond_to?(:response) ? (error.response || {}) : {}
    body = response[:body]
    body = JSON.parse(body) if body.is_a?(String)
    provider = body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
    metadata = {
      "error_class" => error.class.name, "stage" => stage,
      "status" => response[:status], "code" => identifier(provider["code"]),
      "provider_type" => identifier(provider["type"]),
      "request_id" => identifier(response.dig(:headers, "x-request-id"))
    }.compact
    if QUOTA_CODES.include?(provider["code"]) || provider["type"] == "insufficient_quota"
      { type: "wardrobe_provider_quota", message: QUOTA_MESSAGE, metadata: metadata }
    elsif response[:status] == 429
      { type: "wardrobe_provider_rate_limit", message: "The AI service is receiving too many requests. Book preparation could not finish; please try again later.", metadata: metadata }
    else
      { type: "wardrobe_preparation_failed", message: "We couldn't prepare the story's outfits. No page images were generated.", metadata: metadata }
    end
  rescue JSON::ParserError
    { type: "wardrobe_preparation_failed", message: "We couldn't prepare the story's outfits. No page images were generated.",
      metadata: { "error_class" => error.class.name, "stage" => stage, "status" => response[:status] }.compact }
  end

  def self.identifier(value)
    value if value.is_a?(String) && value.length <= 150 && value.match?(/\A[[:alnum:]_.:-]+\z/)
  end
end
