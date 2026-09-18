# frozen_string_literal: true

class PageIllustrationGeneration
  MAX_ATTEMPTS = 3

  def self.state(illustration)
    illustration.generation_metadata.fetch("page_generation", {})
  end

  def self.attempts(illustration)
    state(illustration).fetch("attempts") do
      # Older pages have already had their original generation request.
      [{ "number" => 1, "status" => "legacy", "prompt" => illustration.original_description }]
    end
  end

  def self.available?(illustration, admin: nil)
    illustration.page && illustration.page.wardrobe_ready? && illustration.original_image.blank? &&
      illustration.page.generation_attempt == illustration.page.book.generation_attempt &&
      !%w[queued running].include?(state(illustration)["status"]) &&
      (admin&.admin? || attempts(illustration).length < MAX_ATTEMPTS)
  end

  def self.reserve!(illustration, retrying:, admin: nil)
    illustration.with_lock do
      return if illustration.original_image.present?
      return unless illustration.page.wardrobe_ready?
      return unless illustration.page.generation_attempt == illustration.page.book.reload.generation_attempt
      current = state(illustration).deep_dup
      return if %w[queued running].include?(current["status"])
      history = current.fetch("attempts") { retrying ? attempts(illustration) : [] }
      return if !retrying && history.any?
      return if history.length >= MAX_ATTEMPTS && !admin&.admin?

      token = SecureRandom.uuid
      history << { "number" => history.length + 1, "status" => "queued", "admin_id" => (admin.id if admin&.admin?),
        "user_id" => illustration.page.book.user_id, "created_at" => Time.current.iso8601 }
      illustration.update!(generation_metadata: illustration.generation_metadata.merge(
        "page_generation" => current.merge("token" => token, "status" => "queued", "attempts" => history)))
      token
    end
  end

  def self.enqueue!(illustration, admin: nil)
    token = reserve!(illustration, retrying: true, admin: admin)
    return false unless token

    enqueue_reserved!(illustration, token)
  end

  def self.enqueue_reserved!(illustration, token)
    job = RegeneratePageIllustrationJob.perform_later(illustration.id, token)
    return true if job && job.successfully_enqueued?

    release_queue_reservation!(illustration, token)
    false
  rescue StandardError
    raise unless token

    release_queue_reservation!(illustration, token)
    false
  end

  def self.release_queue_reservation!(illustration, token)
    illustration.with_lock do
      current = state(illustration).deep_dup
      return unless current["token"] == token && current["status"] == "queued"

      current["attempts"].pop
      current["status"] = "enqueue_failed"
      current["queue_failures"] ||= []
      current["queue_failures"] << { "token" => token, "recorded_at" => Time.current.iso8601 }
      illustration.update!(generation_metadata: illustration.generation_metadata.merge("page_generation" => current))
    end
  end

  def self.perform!(illustration, token)
    claimed = illustration.with_lock do
      current = state(illustration).deep_dup
      if current["token"] == token && current["status"] == "queued"
        current["status"] = "running"
        current["attempts"].last["status"] = "running"
        illustration.update!(generation_metadata: illustration.generation_metadata.merge("page_generation" => current))
        true
      end
    end
    return unless claimed

    book = illustration.page.book.reload
    references_ready = illustration.page.wardrobe_required? ? illustration.page.wardrobe_ready? : book.characters_ready_for_generation?
    unless illustration.page.generation_attempt == book.generation_attempt && references_ready
      finish!(illustration, "cancelled")
      return
    end
    if illustration.original_image.present?
      finish!(illustration, "succeeded")
      return
    end

    if attempts(illustration).length > 1
      revised = PageIllustrationPrompt.call(illustration)
      raise "Prompt revision returned an empty or unchanged prompt" if revised.blank? || revised == illustration.original_description
      illustration.update!(original_description: revised)
    end
    current = state(illustration).deep_dup
    current["attempts"].last["prompt"] = illustration.specifications
    illustration.update!(prompt: illustration.specifications,
      generation_metadata: illustration.generation_metadata.merge("page_generation" => current))

    data = illustration.gpt_image_1_edit(book.characters)
    if data.present?
      illustration.extract_image_base64(data)
      raise "Image storage did not produce an illustration" unless illustration.reload.original_image.present?
      finish!(illustration, "succeeded")
      book.refresh_generation_status!(attempt: illustration.page.generation_attempt)
    else
      finish!(illustration, "rejected")
      book.enqueue_illustration_retry!(illustration, actor: nil)
    end
  rescue StandardError => error
    raise unless claimed

    finish!(illustration, "failed", error: error.class.name)
    book.record_generation_failure!(illustration: illustration,
      failure: { "type" => "page_image_generation_failed", "message" => "An illustration could not be generated.",
        "error_class" => error.class.name }, request: { "prompt" => illustration.prompt }) if book
  ensure
    book&.reload&.send(:broadcast_generation_state) if claimed
  end

  def self.finish!(illustration, status, error: nil)
    illustration.with_lock do
      current = state(illustration).deep_dup
      current["status"] = status
      current["attempts"].last.merge!("status" => status, "finished_at" => Time.current.iso8601,
        "error_class" => error, "failure" => illustration.generation_metadata["failure"])
      illustration.update!(generation_metadata: illustration.generation_metadata.merge("page_generation" => current))
    end
  end
end
