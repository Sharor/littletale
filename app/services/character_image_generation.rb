# frozen_string_literal: true

require "base64"
require "open-uri"
require "stringio"
require "tempfile"

class CharacterImageGeneration
  FILENAME = "character.png"
  CONTENT_TYPE = "image/png"
  IMAGE_SIZE = "1024x1024"
  DESCRIPTION_PROMPT_VERSION = "2"
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
    response, prior_refusals = if photo_attached?
      [ edit_photo, [] ]
    elsif structured_description?
      generate_from_description
    else
      [ generate_from_prompt(assessment.prompt), [] ]
    end
    bytes = response.dig("data", 0, "b64_json") ? decode_image(response) : download_image(response)

    {
      io: StringIO.new(bytes.b).tap(&:binmode),
      filename: FILENAME,
      content_type: CONTENT_TYPE,
      request_id: sanitized_value(response["id"] || response["request_id"]),
      prior_refusals: prior_refusals
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
    parameters = {
      prompt: photo_isolation_prompt,
      model: assessment.generation_model,
      size: IMAGE_SIZE
    }
    if assessment.is_a?(CharacterImageAssessment)
      assessment.update!(metadata: assessment.metadata.merge("generation_request" => {
        "endpoint" => "/v1/images/edits", "parameters" => parameters
      }))
    end

    Tempfile.create([ "character-source", ".png" ]) do |file|
      source_image.write(file.path)
      client.images.edit(parameters: parameters.merge(image: [ file.path ]))
    end
  ensure
    source_image&.destroy!
  end

  def photo_isolation_prompt
    <<~PROMPT
      #{assessment.prompt}

      Subject selection and composition requirements:
      Depict exactly one person from the source photo: the person most clearly in focus.
      Judge focus by facial sharpness and visual prominence. Use central position and apparent size only to break a close tie.
      The selected person can be a baby, child, or adult. Do not prefer an adult because of age or caregiving role.
      If the selected person is a baby, retain the baby and exclude the adults. If the selected person is an adult, retain that adult and exclude babies and children.
      Exclude every other person completely from the generated image. Include no secondary faces, heads, limbs, bodies, silhouettes, reflections, or background people.
      If the selected person is holding or touching another person, depict only the selected person. Do not combine features from different people.
      Preserve the selected person's recognizable facial features, hair, skin tone, apparent age, and clothing character while rendering one standalone storybook character.
      The generated image must contain one character only on the requested plain background, with no text.
    PROMPT
  end

  def generate_from_description
    [ generate_from_prompt(description_prompt), [] ]
  rescue Faraday::Error => first_error
    raise unless explicit_refusal?(first_error)

    prior_refusal = refusal_from(first_error).metadata
    begin
      [ generate_from_prompt(description_prompt(reduced: true)), [ prior_refusal ] ]
    rescue Faraday::Error => second_error
      raise unless explicit_refusal?(second_error)

      refusal = refusal_from(second_error)
      raise Refused.new(public_reason: refusal.public_reason,
        metadata: refusal.metadata.merge(
          "description_prompt_version" => DESCRIPTION_PROMPT_VERSION,
          "prior_refusals" => [ prior_refusal ]
        ))
    end
  end

  def generate_from_prompt(prompt)
    parameters = {
      prompt: prompt,
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

  def structured_description?
    description_details.present?
  end

  def description_details
    return @description_details if defined?(@description_details)

    json = assessment.prompt.split("Character details:\n", 2).second
    parsed = JSON.parse(json) if json
    @description_details = parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    @description_details = nil
  end

  def description_prompt(reduced: false)
    # Rebuild app-owned character data instead of forwarding old safety wording.
    # Keep provider instructions focused on the intended family-storybook depiction.
    details = description_details
    age = details["age"].to_i
    age_phrase = age.positive? ? "#{age}-year-old" : "age-appropriate"
    gender = safe_description_value(details["gender"])
    ethnicity = safe_description_value(details["ethnicity"])
    eye_color = safe_description_value(details["eye_color"])
    hair_color = safe_description_value(details["hair_color"])
    hair_style = safe_description_value(details["hair_style"])

    if reduced
      appearance = [ eye_color && "#{eye_color.downcase} eyes",
        hair_color && "#{hair_color.downcase} hair",
        hair_style && "hair worn in #{hair_style.downcase}" ].compact.join(", ")
      return <<~PROMPT
        Simple family storybook portrait of one fictional #{age_phrase} character#{appearance.present? ? " with #{appearance}" : ""}.
        Use an ordinary everyday outfit suitable for that age and a relaxed neutral standing pose.
        Use full color on an entirely light brown background. Include no other people, objects, scenery, or text.
      PROMPT
    end

    identity = [ ethnicity, gender ].compact.map(&:downcase).join(" ")
    identity = "character" if identity.blank?
    appearance = [ eye_color && "#{eye_color.downcase} eyes",
      hair_color && "#{hair_color.downcase} hair",
      hair_style && "hair worn in #{hair_style.downcase}" ].compact.join(", ")
    roles = Array(details["roles"]).filter_map { |role| safe_description_value(role) }

    <<~PROMPT
      Create one wholesome family storybook character in Western children's book style, full color and high detail.
      Depict a #{age_phrase} #{identity}#{appearance.present? ? " with #{appearance}" : ""}.
      Dress the character in ordinary age-appropriate everyday clothing and show a relaxed neutral standing pose.
      Show the character alone on an entirely light brown background, without objects, scenery, action, conflict, or text.
      #{roles.present? ? "Render these roles only as gentle personality or appearance details: #{roles.join(", ")}." : "Do not add traits or details that were not supplied."}
    PROMPT
  end

  def safe_description_value(value)
    return unless value.is_a?(String)

    value = value.squish
    return if value.blank? || value.length > 50
    return unless value.match?(/\A[[:alnum:] '\/-]+\z/)
    return if value.match?(/sex|nude|naked|erotic|porn|fetish|lingerie|underwear|genital|breast/i)

    value
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
