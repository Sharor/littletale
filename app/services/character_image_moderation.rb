require "base64"
require "mini_magick"

class CharacterImageModeration
  MODEL = "omni-moderation-latest"
  MAX_IMAGE_BYTES = 20.megabytes
  SUPPORTED_IMAGE_TYPES = {
    "image/jpeg" => "JPEG",
    "image/png" => "PNG",
    "image/webp" => "WEBP",
    "image/gif" => "GIF"
  }.freeze
  INVALID_TYPE_MESSAGE = "Please replace the photo with a valid JPEG, PNG, WEBP, or GIF image."
  TOO_LARGE_MESSAGE = "Please replace the photo with an image smaller than 20 MB."
  UNREADABLE_MESSAGE = "Please replace the photo with a valid image that can be opened."

  def self.call(assessment)
    new(assessment).call
  end

  def initialize(assessment)
    @assessment = assessment
  end

  def call
    photo_input = build_photo_input
    return photo_input if decision?(photo_input)

    response = client.moderations(parameters: {
      model: MODEL,
      input: [ { type: "text", text: assessment.prompt }, photo_input ].compact
    })

    decision_from(response, photo_submitted: photo_input.present?)
  end

  private

  attr_reader :assessment

  def build_photo_input
    photo = assessment.photo
    return unless photo&.attached?

    blob = photo.blob
    return rejected("image_too_large", TOO_LARGE_MESSAGE) if blob.byte_size > MAX_IMAGE_BYTES

    declared_type = blob.content_type.to_s.downcase
    return rejected("unsupported_image_type", INVALID_TYPE_MESSAGE) unless SUPPORTED_IMAGE_TYPES.key?(declared_type)

    bytes = photo.download
    actual_type = decoded_content_type(bytes)
    return rejected("unsupported_image_type", INVALID_TYPE_MESSAGE) unless actual_type == declared_type

    {
      type: "image_url",
      image_url: { url: "data:#{actual_type};base64,#{Base64.strict_encode64(bytes)}" }
    }
  rescue MiniMagick::Error
    rejected("unreadable_image", UNREADABLE_MESSAGE)
  end

  def decoded_content_type(bytes)
    image = MiniMagick::Image.read(bytes)
    SUPPORTED_IMAGE_TYPES.key(image.type.to_s.upcase)
  ensure
    image&.destroy!
  end

  def decision_from(response, photo_submitted:)
    result = response_result(response)
    metadata = sanitized_metadata(response, result)
    return needs_review("moderation_response_malformed", metadata) unless valid_response?(response, result)

    if result.fetch("flagged") || result.fetch("categories").value?(true)
      needs_review("moderation_flagged", metadata)
    elsif photo_submitted && !assessed_input_type?(result, "image")
      needs_review("moderation_image_not_assessed", metadata)
    elsif !assessed_input_type?(result, "text")
      needs_review("moderation_text_not_assessed", metadata)
    else
      {
        outcome: "approved",
        internal_reason: "moderation_clear",
        public_reason: nil,
        metadata: metadata
      }
    end
  end

  def response_result(response)
    results = response["results"] if response.is_a?(Hash)
    results.first if results.is_a?(Array) && results.one? && results.first.is_a?(Hash)
  end

  def valid_response?(response, result)
    return false unless response.is_a?(Hash)
    return false unless response["id"].is_a?(String) && response["id"].present?
    return false unless response["model"].is_a?(String) && response["model"].present?
    return false unless [ true, false ].include?(result&.fetch("flagged", nil))

    categories = result["categories"]
    scores = result["category_scores"]
    input_types = result["category_applied_input_types"]

    categories.is_a?(Hash) && categories.present? && categories.values.all? { |value| [ true, false ].include?(value) } &&
      scores.is_a?(Hash) && scores.keys.sort == categories.keys.sort && scores.values.all? { |value| value.is_a?(Numeric) && value.finite? && value.between?(0, 1) } &&
      input_types.is_a?(Hash) && input_types.keys.sort == categories.keys.sort &&
      input_types.values.all? { |types| types.is_a?(Array) && (types - [ "text", "image" ]).empty? }
  end

  def sanitized_metadata(response, result)
    return {} unless response.is_a?(Hash)

    {
      "id" => response["id"],
      "model" => response["model"],
      "categories" => result&.[]("categories"),
      "scores" => result&.[]("category_scores")&.is_a?(Hash) ? result["category_scores"].select { |_key, value| value.is_a?(Numeric) && value.finite? } : nil,
      "applied_input_types" => result&.[]("category_applied_input_types")
    }.compact
  end

  def assessed_input_type?(result, input_type)
    result.fetch("category_applied_input_types").values.any? { |types| types.include?(input_type) }
  end

  def client
    @client ||= OpenAI::Client.new(access_token: ENV.fetch("OPENAI_ACCESS_TOKEN", nil))
  end

  def decision?(value)
    value.is_a?(Hash) && value.key?(:outcome)
  end

  def rejected(internal_reason, public_reason)
    {
      outcome: "rejected",
      internal_reason: internal_reason,
      public_reason: public_reason,
      metadata: {}
    }
  end

  def needs_review(internal_reason, metadata)
    {
      outcome: "needs_review",
      internal_reason: internal_reason,
      public_reason: nil,
      metadata: metadata
    }
  end
end
