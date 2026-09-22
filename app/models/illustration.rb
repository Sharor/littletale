class Illustration < ApplicationRecord
  belongs_to :page, optional: true
  belongs_to :character, optional: true

  mount_uploader :original_image, ImageUploader

  attr_accessor :original_image_url

  # Generation of story book images with characters
  def generate_image_v1(characters)
    return if self.original_image.present?

    token = PageIllustrationGeneration.reserve!(self, retrying: false)
    PageIllustrationGeneration.perform!(self, token) if token
  end

  def extract_image_base64(data)
    blob = Base64.decode64(data.dig("data", 0, "b64_json"))

    begin
      image = MiniMagick::Image.read(blob)
      filename = "./tmp/tmp_gpt_image_one_#{SecureRandom.hex(8)}.png"
      image.write filename
      self.original_image = MiniMagick::Image.open(filename)
      save
    ensure
      image&.destroy!
      File.delete(filename) if filename && File.exist?(filename)
    end
  end

  def gpt_image_1_edit(characters)
    images = []
    begin
      if page&.wardrobe_required?
        raise "Page wardrobe is not ready" unless page.wardrobe_ready?

        page.book_outfits.each_with_index do |outfit, index|
          ext = File.extname(outfit.image.filename.to_s).presence || ".png"
          temp = Tempfile.new([ "wardrobe_#{index}", ext ])
          images << temp
          temp.binmode
          temp.write(outfit.image.download)
          temp.rewind
        end
      else
        characters.each_with_index do |character, index|
          uploader = character.illustration.original_image
          ext = File.extname(uploader.path).presence || ".png"

          if uploader.file.respond_to?(:url) && uploader.file.url.start_with?("http")
            # Use Tempfile.new to guarantee a real file on disk with the correct extension
            # This is the most reliable way to satisfy "failed to determine mimetype"
            temp = Tempfile.new([ "image_#{index}", ext ])
            images << temp
            temp.binmode
            temp.write(URI.parse(uploader.url).read)
            temp.rewind
          else
            # Local development path
            images << File.open(Rails.root.join("public", uploader.path), "rb")
          end
        end
      end

      # 2. Call the client
      parameters = {
        prompt: specifications(),
        model: "gpt-image-1",
        size: "1024x1024"
      }
      if page&.wardrobe_required? && images.empty?
        client.images.generate(parameters: parameters)
      else
        client.images.edit(parameters: parameters.merge(image: images))
      end

    rescue Faraday::BadRequestError => e
        Rails.logger.error("STATUS: #{e.response[:status]}")
        Rails.logger.error("HEADERS: #{e.response[:headers]}")
        Rails.logger.error("BODY: #{e.response[:body]}")
        return record_moderation_failure!(e, characters) if moderation_blocked?(e)

        raise e # Don't retry other 400s; the payload is the problem

    ensure
      # 3. Final cleanup to prevent memory leaks in Docker
      images.each { |image| image.is_a?(Tempfile) ? image.close! : image.close }
    end
  end

  def cartoonify(characters)
    image = MiniMagick::Image.read(characters.first.photo.download)
    image.format "png"
    image_file = File.open(image.path, "rb")
    data = client.images.edit(parameters: { prompt: single_specification(), model: "gpt-image-1", image: [ image_file ], size: "1024x1024" })
    extract_image_base64(data)
  rescue Faraday::BadRequestError => e
    # Specific handling for the API failure
    Rails.logger.error("!!! API ERROR !!!")
    Rails.logger.error("STATUS: #{e.response[:status]}")
    Rails.logger.error("HEADERS: #{e.response[:headers]}")
    Rails.logger.error("BODY: #{e.response[:body]}")
    # You might NOT want to retry if it's a 400 Bad Request,
    # as retrying won't fix a broken payload.
    raise e

  rescue StandardError => e
    # General handling for everything else (NoMethodError, Timeout, etc.)
    Rails.logger.error("!!! SYSTEM ERROR: #{e.message} !!!")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    Rails.logger.info(characters.inspect)

    sleep(1)
    Rails.logger.info("Retrying to create image...")
    retry # Warning: Ensure you have a retry limit elsewhere!
  end

  # Sort out bad images - for example Olivia with bathing suit triggered "sexual" content denial. Caught below.
  #   begin
  #   response = OpenAI::Client.new.images.edit(parameters)
  # rescue Faraday::BadRequestError => e
  #   puts "STATUS: #{e.response[:status]}"
  #   puts "HEADERS: #{e.response[:headers]}"
  #   puts "BODY: #{e.response[:body]}"
  #   raise e # optional, re-raise if you want normal error handling after
  # end


  def single_specification
    "Do not write any letters in the image. Use color and do not make the image monochromatic. Use the provided image(s) to make a new image, and strip all background. Focus only on human beings. Image should be in #{style_and_resolution}:\n Make only the character, nothing else. Make the background entirely light brown."
  end

  def specifications
    scene = "Do not write any letters in the image. Use color and do not make the image monochromatic. Use the provided image(s) to make a new image using this description:\n#{self.original_description}"
    scene = "#{scene}\n\n#{page.wardrobe_instructions}" if page&.wardrobe_required?
    art_direction = page&.book&.art_style_prompt
    scene = "#{scene}\n\nArt direction: #{art_direction} Apply this art direction throughout the complete image. " \
      "Reference images establish character identity and clothing only; their rendering style must not override this art direction." if art_direction
    "#{scene}\n\nComposition: Show one scene at a single moment, not a montage or sequence. " \
      "Depict each character present exactly once, with one body per character. " \
      "If the description mentions several actions, choose one coherent moment instead of drawing the same person again. " \
      "Do not repeat characters in reflections, phone screens, photographs, inset images or background figures. " \
      "For a selfie, show the back of the phone. " \
      "The supplied images and saved outfits are identity references, not additional people to include. " \
      "Include only the characters participating in this scene; keep their identities distinct."
  end

  # Generation of single characters
  def generate_single_character(character_description)
    @tries = 0
    background = "Make only the character, nothing else. Make the background entirely light brown."
    prompt = "#{build_prompt} Character description: #{character_description}\n#{background}"

    Rails.logger.info("Generating image ID: #{self.character_id} - prompt: #{prompt}")
    data = dalle_response(prompt)
    # TODO handle robustness when chatgpt fails to deliver.

    self.original_description = prompt
    self.image_url = data.dig("data", 0, "url")# data[:data].first[:url]
    self.original_image = MiniMagick::Image.open(image_url)
    Rails.logger.info("Finished image for character with ID: #{self.id}.")
    save
  end

  def build_prompt
    "plaintext\nImage should be in #{style_and_resolution}:\n"
  end

  def dalle_response(prompt)
    client.images.generate(parameters: { prompt: prompt, model: "dall-e-3", size: "1024x1024", quality: "standard", n: 1 })
  rescue StandardError => e
    Rails.logger.error(e)
    Rails.logger.error("Failed image generation w/message: #{e.response[:body][:message]}")
    sleep(1)
    Rails.logger.info("Retrying to create image...")
    retry if (@tries += 1) < 5
  end

  def image_prompt_instruction(characters, section)
    "#{build_prompt} #{character_descriptions(characters)}, #{actions_and_emotions(section)}, #{setting_and_environment(section)}"
  end

  def style_and_resolution
    "Western children's book style, 4k resolution"
  end

  def client
    OpenAI::Client.new(access_token: ENV.fetch("OPENAI_ACCESS_TOKEN", nil))
  end

  private

  def moderation_blocked?(error)
    error.response.dig(:body, "error", "code") == "moderation_blocked"
  end

  def record_moderation_failure!(error, characters)
    api_error = error.response.dig(:body, "error") || {}
    failure = {
      "type" => "openai_image_moderation_blocked",
      "message" => api_error["message"],
      "code" => api_error["code"],
      "moderation_stage" => api_error.dig("moderation_details", "moderation_stage"),
      "categories" => api_error.dig("moderation_details", "categories"),
      "request_id" => error.response.dig(:headers, "x-request-id"),
      "recorded_at" => Time.current.iso8601
    }
    request = {
      "endpoint" => "/v1/images/edits",
      "model" => "gpt-image-1",
      "size" => "1024x1024",
      "prompt" => specifications,
      "character_ids" => characters.map(&:id),
      "reference_images" => if page&.wardrobe_required?
        page.book_outfits.map do |outfit|
          { "character_id" => outfit.character_id, "image" => outfit.image.filename.to_s }
        end
      else
        characters.map do |character|
          reference = character.illustration
          { "character_id" => character.id, "illustration_id" => reference&.id, "image" => reference&.original_image&.identifier }
        end
      end
    }

    update!(prompt: request["prompt"], generation_metadata: generation_metadata.merge("request" => request, "failure" => failure))
    page.book.record_generation_failure!(illustration: self, failure: failure, request: request)
    nil
  end
end
