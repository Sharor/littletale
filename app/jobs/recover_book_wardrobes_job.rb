# frozen_string_literal: true

class RecoverBookWardrobesJob < ApplicationJob
  queue_as :default

  def perform
    BookWardrobePlan.find_each do |plan|
      next unless plan.current?
      if plan.status == "planning" && plan.claimed_at && plan.claimed_at < 1.hour.ago
        plan.fail!(type: "wardrobe_preparation_failed", message: "Story and outfit preparation was interrupted. No page images were generated.")
        next
      end
      next unless %w[pending preparing ready].include?(plan.status)
      if plan.status == "pending"
        GenerateBookJob.perform_later(plan.book_id, plan.generation_attempt)
        next
      end
      plan.book_outfits.where(status: "generating").where("claimed_at < ?", 1.hour.ago).find_each do |outfit|
        unknown = false
        outfit.with_lock do
          next unless outfit.status == "generating" && outfit.claimed_at < 1.hour.ago
          unknown = !outfit.image.attached?
          outfit.update!(status: unknown ? "outcome_unknown" : "ready",
            generation_metadata: outfit.generation_metadata.merge("recovered_at" => Time.current.iso8601))
        end
        if unknown
          plan.fail!(type: "wardrobe_image_failed", message: "Outfit generation was interrupted and its result is unknown. It has not been retried.",
            metadata: { "outfit_id" => outfit.id })
        end
      end
      next if plan.reload.status == "failed"
      BookWardrobePreparation.queue_outfits(plan)
    end
  end
end
