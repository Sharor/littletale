class GenerateCharacterImageJob < ApplicationJob
  queue_as :default

  def perform(attempt_id)
    attempt = CharacterImageGenerationAttempt.find_by(id: attempt_id)
    return unless attempt
    request = attempt.request
    claimed = false
    request.user.with_lock do
      attempt.with_lock do
        if request.current? && request.screening_status == "approved" &&
            (attempt.status == "reserved" || (attempt.status == "failed" && attempt.result_image.attached?))
          attempt.update!(status: "in_progress", started_at: Time.current)
          request.character.in_progress!
          claimed = true
        end
      end
    end
    return unless claimed

    unless attempt.result_image.attached?
      result = CharacterImageGeneration.call(request.assessment)
      attempt.result_image.attach(io: result.fetch(:io), filename: result.fetch(:filename), content_type: result.fetch(:content_type))
      failure_metadata = attempt.failure_metadata
      if result[:prior_refusals].present?
        failure_metadata = failure_metadata.merge("prior_refusals" =>
          Array(failure_metadata["prior_refusals"]) + result[:prior_refusals])
      end
      attempt.update!(provider_request_id: result[:request_id], failure_metadata: failure_metadata)
    end
    publish_result!(attempt)
  rescue CharacterImageGeneration::Refused => error
    attempt.update!(status: "failed", finished_at: Time.current,
      failure_metadata: attempt.failure_metadata.merge(error.metadata))
    request.reject_by_provider!(public_reason: error.public_reason, metadata: error.metadata)
    fail_character(request)
  rescue StandardError => error
    raise unless claimed
    # A response can be lost after the provider charged for it. Never resend it.
    definite_bad_request = error.is_a?(Faraday::BadRequestError)
    status = attempt.result_image.attached? || definite_bad_request ? "failed" : "outcome_unknown"
    attempt.update!(status: status, finished_at: Time.current, failure_metadata: attempt.failure_metadata.merge(failure_metadata(error)))
    fail_character(request)
  end

  private

  def failure_metadata(error)
    metadata = { "error_class" => error.class.name }
    return metadata unless error.is_a?(Faraday::Error) && error.response

    metadata["http_status"] = error.response[:status]
    body = error.response[:body]
    body = JSON.parse(body) if body.is_a?(String)
    provider = body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
    { "code" => provider["code"], "param" => provider["param"],
      "request_id" => error.response.dig(:headers, "x-request-id") }.each do |key, value|
      metadata[key] = value.first(100) if value.is_a?(String) && value.match?(/\A[[:alnum:]_.:\/-]+\z/)
    end
    metadata
  rescue JSON::ParserError
    metadata
  end

  def publish_result!(attempt)
    request = attempt.request
    attempt.result_image.open do |file|
      image = MiniMagick::Image.new(file.path)
      raise "Image result is invalid" unless image.valid?
      request.user.with_lock do
        character = request.reload.character
        if character
          character.with_lock do
            if request.current?
              # Preserve prior illustrations for attempt history, but keep the
              # character's has_one association unambiguous after replacement.
              Illustration.where(character_id: character.id).update_all(character_id: nil)
              illustration = Illustration.create!(character: character, original_description: request.assessment.prompt,
                original_image: file)
              attempt.update!(illustration: illustration)
              character.illustration = illustration
              character.completed!
            end
          end
        end
        attempt.update!(status: attempt.illustration_id ? "completed" : "failed", finished_at: Time.current)
      end
    end
    request.character&.broadcast_image_status if request.current?
  end

  def fail_character(request)
    request.user.with_lock do
      if request.current?
        request.character.failed!
        request.character.broadcast_image_status
      end
    end
  end
end
