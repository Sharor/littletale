# frozen_string_literal: true

require "base64"
require "json"

module GenerationProviders
  class Gemini
    BASE_URL = "https://generativelanguage.googleapis.com"
    TEXT_MODEL = "gemini-3.8-flash"
    IMAGE_MODEL = "gemini-3.1-flash-image"
    MODERATION_CATEGORIES = %w[
      hate harassment self_harm sexual sexual_minors violence violence_graphic
    ].freeze

    STORY_SCHEMA = {
      type: "array",
      items: {
        type: "object",
        properties: {
          story: { type: "string" },
          image: { type: "string" }
        },
        required: %w[story image],
        additionalProperties: false
      }
    }.freeze

    WARDROBE_SCHEMA = {
      type: "object",
      properties: {
        outfits: {
          type: "array",
          items: {
            type: "object",
            properties: {
              character_id: { type: "integer" },
              key: { type: "string" },
              description: { type: "string" },
              pages: { type: "array", items: { type: "integer" } }
            },
            required: %w[character_id key description pages],
            additionalProperties: false
          }
        }
      },
      required: [ "outfits" ],
      additionalProperties: false
    }.freeze

    CATEGORIZATION_SCHEMA = {
      type: "object",
      properties: {
        categories: { type: "array", items: { type: "string" }, minItems: 1, maxItems: 3 }
      },
      required: [ "categories" ],
      additionalProperties: false
    }.freeze

    MODERATION_SCHEMA = {
      type: "object",
      properties: {
        flagged: { type: "boolean" },
        categories: {
          type: "object",
          properties: MODERATION_CATEGORIES.to_h { |category| [ category, { type: "boolean" } ] },
          required: MODERATION_CATEGORIES,
          additionalProperties: false
        },
        category_scores: {
          type: "object",
          properties: MODERATION_CATEGORIES.to_h do |category|
            [ category, { type: "number", minimum: 0, maximum: 1 } ]
          end,
          required: MODERATION_CATEGORIES,
          additionalProperties: false
        }
      },
      required: %w[flagged categories category_scores],
      additionalProperties: false
    }.freeze

    STRUCTURED_SCHEMAS = {
      "book_story" => STORY_SCHEMA,
      "book_wardrobe_plan" => WARDROBE_SCHEMA,
      "book_categorization" => CATEGORIZATION_SCHEMA,
      "character_screening" => MODERATION_SCHEMA
    }.freeze

    def initialize(
      operation:,
      api_key: ENV.fetch("GEMINI_API_KEY", nil),
      text_model: ENV.fetch("GEMINI_TEXT_MODEL", TEXT_MODEL),
      image_model: ENV.fetch("GEMINI_IMAGE_MODEL", IMAGE_MODEL),
      connection: nil
    )
      @operation = operation.to_s
      @api_key = api_key
      @text_model = text_model
      @image_model = image_model
      @connection = connection || Faraday.new(url: BASE_URL) do |faraday|
        faraday.options.open_timeout = 10
        faraday.options.timeout = 120
        faraday.response :raise_error
      end
    end

    def model_for(capability, _parameters)
      %i[generate edit].include?(capability.to_sym) ? @image_model : @text_model
    end

    def chat(parameters:)
      messages = parameter(parameters, :messages) || []
      payload = {
        model: model_for(:chat, parameters),
        input: conversation_input(messages),
        store: false
      }

      system_instruction = system_instruction(messages)
      payload[:system_instruction] = system_instruction if system_instruction.present?

      max_tokens = parameter(parameters, :max_tokens)
      payload[:generation_config] = { max_output_tokens: max_tokens } if max_tokens

      schema = STRUCTURED_SCHEMAS[@operation]
      payload[:response_format] = text_response_format(schema) if schema

      body = interaction(payload)
      text = output_content(body, "text")&.fetch("text", nil)
      raise InvalidResponse, "Gemini returned no text output" unless text.is_a?(String) && text.present?

      {
        "id" => body["id"],
        "model" => body["model"] || model_for(:chat, parameters),
        "choices" => [ { "message" => { "content" => text } } ]
      }
    end

    def generate(parameters:)
      image_request(parameters, references: [])
    end

    def edit(parameters:)
      image_request(parameters, references: Array(parameter(parameters, :image)))
    end

    def moderations(parameters:)
      inputs = Array(parameter(parameters, :input))
      image_inputs = inputs.filter_map { |input| moderation_image(input) }
      text = inputs.filter_map { |input| moderation_text(input) }.join("\n\n")
      interaction_inputs = image_inputs.dup
      interaction_inputs << { type: "text", text: text } if text.present?

      body = interaction(
        model: model_for(:moderations, parameters),
        input: interaction_inputs,
        system_instruction: moderation_instruction,
        store: false,
        response_format: text_response_format(MODERATION_SCHEMA)
      )
      content = output_content(body, "text")&.fetch("text", nil)
      result = parse_moderation(content)
      input_types = [ "text" ]
      input_types << "image" if image_inputs.any?
      result["category_applied_input_types"] = MODERATION_CATEGORIES.to_h do |category|
        [ category, input_types ]
      end

      {
        "id" => body["id"],
        "model" => body["model"] || model_for(:moderations, parameters),
        "results" => [ result ]
      }
    end

    private

    def interaction(payload)
      response = @connection.post("/v1beta/interactions") do |request|
        request.headers["Content-Type"] = "application/json"
        request.headers["x-goog-api-key"] = @api_key.to_s
        request.body = JSON.generate(payload)
      end
      body = parse_body(response.body)
      raise InvalidResponse, "Gemini returned an invalid response" unless body.is_a?(Hash)
      raise_content_rejected!(body, response.status, response.headers) if safety_rejection?(body)
      raise InvalidResponse, "Gemini did not complete the request" unless body["status"] == "completed"

      body
    rescue Faraday::BadRequestError => error
      raise unless safety_rejection?(error_body(error))

      raise_content_rejected!(error_body(error), error.response&.dig(:status), error.response&.dig(:headers) || {})
    end

    def image_request(parameters, references:)
      input = references.map { |reference| inline_image(reference) }
      input << { type: "text", text: parameter(parameters, :prompt).to_s }
      body = interaction(
        model: model_for(:generate, parameters),
        input: input,
        store: false,
        response_format: {
          type: "image",
          mime_type: "image/png",
          aspect_ratio: "1:1",
          image_size: "1K"
        }
      )
      image = output_content(body, "image")
      data = image&.fetch("data", nil)
      raise InvalidResponse, "Gemini returned no image output" unless data.is_a?(String) && data.present?

      {
        "id" => body["id"],
        "model" => body["model"] || model_for(:generate, parameters),
        "data" => [ { "b64_json" => data } ]
      }
    end

    def conversation_input(messages)
      Array(messages).filter_map do |message|
        role = parameter(message, :role).to_s
        next if %w[developer system].include?(role)

        content = parameter(message, :content)
        next if content.nil?

        label = role == "assistant" ? "ASSISTANT EXAMPLE" : role.upcase.presence || "USER"
        "#{label}:\n#{content.is_a?(String) ? content : JSON.generate(content)}"
      end.join("\n\n")
    end

    def system_instruction(messages)
      Array(messages).filter_map do |message|
        next unless %w[developer system].include?(parameter(message, :role).to_s)

        content = parameter(message, :content)
        content.is_a?(String) ? content : JSON.generate(content)
      end.join("\n\n")
    end

    def output_content(body, type)
      Array(body["steps"]).reverse_each do |step|
        next unless step.is_a?(Hash) && step["type"] == "model_output"

        output = Array(step["content"]).find { |item| item.is_a?(Hash) && item["type"] == type }
        return output if output
      end
      nil
    end

    def inline_image(reference)
      bytes, filename = if reference.respond_to?(:read)
        position = reference.pos if reference.respond_to?(:pos)
        reference.rewind if reference.respond_to?(:rewind)
        [ reference.read, reference.respond_to?(:path) ? reference.path : nil ]
      else
        [ File.binread(reference.to_s), reference.to_s ]
      end

      {
        type: "image",
        mime_type: image_mime_type(filename),
        data: Base64.strict_encode64(bytes)
      }
    ensure
      reference.seek(position) if !position.nil? && reference.respond_to?(:seek)
    end

    def image_mime_type(filename)
      case File.extname(filename.to_s).downcase
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".webp" then "image/webp"
      when ".gif" then "image/gif"
      else "image/png"
      end
    end

    def moderation_image(input)
      return unless parameter(input, :type).to_s == "image_url"

      url = parameter(parameter(input, :image_url) || {}, :url).to_s
      match = url.match(%r{\Adata:(image/(?:jpeg|png|webp|gif));base64,([A-Za-z0-9+/=]+)\z})
      raise InvalidResponse, "Moderation image input is invalid" unless match

      { type: "image", mime_type: match[1], data: match[2] }
    end

    def moderation_text(input)
      parameter(input, :text) if parameter(input, :type).to_s == "text"
    end

    def moderation_instruction
      "Classify the supplied children's story character text and optional image for safety. " \
        "Return only the requested JSON. Scores must be between 0 and 1."
    end

    def parse_moderation(content)
      parsed = JSON.parse(content.to_s)
      categories = parsed["categories"]
      scores = parsed["category_scores"]
      complete = parsed.key?("flagged") && categories.is_a?(Hash) && scores.is_a?(Hash) &&
        MODERATION_CATEGORIES.all? do |category|
          [ true, false ].include?(categories[category]) && scores[category].is_a?(Numeric)
        end
      raise InvalidResponse, "Gemini returned invalid moderation output" unless complete

      {
        "flagged" => parsed["flagged"] == true || categories.value?(true),
        "categories" => categories.slice(*MODERATION_CATEGORIES),
        "category_scores" => scores.slice(*MODERATION_CATEGORIES)
      }
    rescue JSON::ParserError
      raise InvalidResponse, "Gemini returned invalid moderation output"
    end

    def text_response_format(schema)
      { type: "text", mime_type: "application/json", schema: schema }
    end

    def parse_body(body)
      return body.stringify_keys if body.is_a?(Hash)

      JSON.parse(body.to_s)
    rescue JSON::ParserError
      nil
    end

    def error_body(error)
      response = error.respond_to?(:response) ? error.response : nil
      body = response.is_a?(Hash) && (response[:body] || response["body"])
      parse_body(body) || {}
    end

    def safety_rejection?(body)
      error = body.is_a?(Hash) ? body["error"] || body[:error] : nil
      return false unless error.is_a?(Hash)

      values = [ error["code"], error[:code], error["status"], error[:status], error["message"], error[:message] ]
      values.compact.join(" ").match?(/safety|block|policy|harm|prohibited/i)
    end

    def raise_content_rejected!(body, status, headers)
      provider_error = body["error"] || {}
      category = provider_error["category"]
      normalized_headers = headers.to_h.transform_keys { |key| key.to_s.downcase }
      request_id = normalized_headers["x-goog-request-id"] || normalized_headers["x-request-id"]
      response = {
        status: Integer(status || 400),
        headers: { "x-request-id" => request_id }.compact,
        body: {
          "error" => {
            "code" => "moderation_blocked",
            "message" => "The provider rejected this content.",
            "category" => category.to_s.presence || "other"
          }
        }
      }
      raise ContentRejected.new(response: response)
    end

    def parameter(hash, key)
      return unless hash.respond_to?(:[])

      hash[key] || hash[key.to_s]
    end
  end
end
