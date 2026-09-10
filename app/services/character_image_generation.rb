# frozen_string_literal: true

require "base64"
require "open-uri"
require "stringio"
require "tempfile"

class CharacterImageGeneration
  FILENAME = "character.png"
  CONTENT_TYPE = "image/png"
  IMAGE_SIZE = "1024x1024"
  REFUSAL_CODES = %w[
    moderation_blocked
    content_policy_violation
    content_filter
  ].freeze
  GENERIC_REFUSAL_REASON = "The image service declined this request without a more specific reason."

  class Refused < StandardError
    attr_reader :public_reason, :metadata

    def initialize(public_reason:, metadata:)
      @public_reason = public_reason
      @metadata = metadata
      super(public_reason)
    end
  end

  def self.call(assessment)
    new(assessment).call
  end

  def initialize(assessment)
    @assessment = assessment
  end

  def call
    response = photo_attached? ? edit_photo : generate_from_prompt
    bytes = response.dig("data", 0, "b64_json") ? decode_image(response) : download_image(response)

    {
      io: StringIO.new(bytes.b).tap(&:binmode),
      filename: FILENAME,
      content_type: CONTENT_TYPE,
      request_id: sanitized_value(response["id"] || response["request_id"])
    }
  rescue Faraday::Error => error
    raise refusal_from(error) if explicit_refusal?(error)

    raise
  end

  private

  attr_reader :assessment

  def photo_attached?
    assessment.photo&.attached?
  end

  def edit_photo
    source_image = MiniMagick::Image.read(assessment.photo.download)
    source_image.format("png")

    Tempfile.create([ "character-source", ".png" ]) do |file|
      source_image.write(file.path)
      client.images.edit(parameters: {
        prompt: assessment.prompt,
        model: assessment.generation_model,
        image: [ file.path ],
        size: IMAGE_SIZE
      })
    end
  ensure
    source_image&.destroy!
  end

  def generate_from_prompt
    parameters = {
      prompt: assessment.prompt,
      model: assessment.generation_model,
      size: IMAGE_SIZE,
      quality: assessment.generation_model.start_with?("gpt-image-") ? "auto" : "standard",
      n: 1
    }
    if assessment.is_a?(CharacterImageAssessment)
      assessment.update!(metadata: assessment.metadata.merge("generation_request" => {
        "endpoint" => "/v1/images/generations", "parameters" => parameters
      }))
    end
    client.images.generate(parameters: parameters)
  end

  def decode_image(response)
    Base64.strict_decode64(response.dig("data", 0, "b64_json"))
  end

  def download_image(response)
    URI.parse(response.dig("data", 0, "url")).open("rb", &:read)
  end

  def client
    @client ||= OpenAI::Client.new(access_token: ENV.fetch("OPENAI_ACCESS_TOKEN", nil))
  end

  def explicit_refusal?(error)
    REFUSAL_CODES.include?(error_code(error).to_s.downcase)
  end

  def refusal_from(error)
    category = error_category(error)
    metadata = {
      "code" => sanitized_value(error_code(error)),
      "request_id" => sanitized_value(response_headers(error)["x-request-id"]),
      "category" => sanitized_value(category)
    }.compact

    Refused.new(public_reason: public_reason(category), metadata: metadata)
  end

  def public_reason(category)
    sanitized_category = sanitized_value(category)
    return GENERIC_REFUSAL_REASON if sanitized_category.nil? || %w[other unknown].include?(sanitized_category.downcase)

    plain_category = sanitized_category.tr("_/-", " ").squish.downcase
    "The image service declined this request because it detected #{plain_category}."
  end

  def error_code(error)
    provider_error(error)["code"]
  end

  def error_category(error)
    provider_data = provider_error(error)
    details = provider_data["moderation_details"].is_a?(Hash) ? provider_data["moderation_details"] : {}
    category = provider_data["category"] || details["category"] || details["categories"]

    case category
    when Array
      category.find { |value| value.is_a?(String) }
    when Hash
      category.find { |_key, flagged| flagged }&.first
    else
      category
    end
  end

  def provider_error(error)
    body = error.response&.fetch(:body, nil)
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
  rescue JSON::ParserError
    {}
  end

  def response_headers(error)
    error.response&.fetch(:headers, {}) || {}
  end

  def sanitized_value(value)
    return unless value.is_a?(String)

    value = value.strip
    return if value.empty? || !value.match?(/\A[[:alnum:]_.:\/-]+\z/)

    value.first(100)
  end
end
