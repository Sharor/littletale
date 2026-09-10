# frozen_string_literal: true

class GenerateBookOutfitJob < ApplicationJob
  queue_as :default

  def perform(outfit_id)
    outfit = BookOutfit.find_by(id: outfit_id)
    return unless outfit
    plan = outfit.book_wardrobe_plan
    return unless plan.current? && plan.status == "preparing"
    claimed = outfit.with_lock do
      if outfit.status == "pending"
        outfit.update!(status: "generating", claimed_at: Time.current,
          generation_metadata: { "user_id" => plan.book.user_id, "prompt" => outfit.description,
            "model" => "gpt-image-1", "started_at" => Time.current.iso8601 })
        true
      end
    end
    return unless claimed

    result = BookWardrobeImageGeneration.call(outfit)
    outfit.image.attach(result.slice(:io, :filename, :content_type))
    outfit.update!(status: "ready", generation_metadata: outfit.generation_metadata.merge(
      "request_id" => result[:request_id], "finished_at" => Time.current.iso8601))
    BookWardrobeDispatch.call(plan)
  rescue BookWardrobeImageGeneration::Refused => error
    outfit.update!(status: "rejected", generation_metadata: outfit.generation_metadata.merge("failure" => error.metadata))
    plan.fail!(type: "wardrobe_image_rejected", message: error.public_reason, metadata: { "outfit_id" => outfit.id }.merge(error.metadata))
  rescue StandardError => error
    raise unless claimed
    outfit.update!(status: outfit.image.attached? ? "ready" : "outcome_unknown",
      generation_metadata: outfit.generation_metadata.merge("error_class" => error.class.name))
    plan.fail!(type: "wardrobe_image_failed", message: "We couldn't finish preparing a character's outfit. Page generation has stopped.",
      metadata: { "outfit_id" => outfit.id, "error_class" => error.class.name })
  end
end
