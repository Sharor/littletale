# frozen_string_literal: true

class BookWardrobePreparation
  def self.call(plan)
    return unless plan.current?
    return BookWardrobeDispatch.call(plan) if plan.ready?
    return if plan.status == "preparing"

    claimed = plan.with_lock do
      if plan.status == "pending"
        plan.update!(status: "planning", claimed_at: Time.current)
        true
      end
    end
    return unless claimed

    stage = "character_snapshot"
    snapshots = plan.book.characters.order(:id).map do |character|
      character.with_lock do
        raise BookWardrobePlan::InvalidPlan, "Character reference unavailable" unless character.image_ready_for_book?
        reference = character.illustration
        reference.with_lock do
          bytes = reference.original_image.read
          blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes.b), filename: "source.png", content_type: "image/png")
          plan.source_images.attach(blob)
          character.attributes.slice(*BookWardrobePlanner::CHARACTER_FIELDS).merge("source_blob_id" => blob.id)
        end
      end
    end
    plan.update!(character_snapshots: snapshots)
    stage = "story"
    story = BookStoryGeneration.call(plan.book, character_snapshots: snapshots)
    plan.validate_story!(story)
    plan.update!(story: story)
    stage = "wardrobe_plan"
    proposal = plan.character_snapshots.empty? ? { "outfits" => [] } : BookWardrobePlanner.call(plan.book, story, character_snapshots: snapshots)
    plan.validate_outfits!(proposal)
    return unless plan.current?

    plan.with_lock do
      return unless plan.current? && plan.status == "planning"
      proposal.fetch("outfits").each do |attributes|
        outfit = plan.book_outfits.create!(character_id: attributes.fetch("character_id"),
          outfit_key: attributes.fetch("key"), description: attributes.fetch("description"),
          page_numbers: attributes.fetch("pages"),
          character_snapshot: plan.character_snapshots.find { |snapshot| snapshot["id"] == attributes["character_id"] })
        outfit.source_image.attach(plan.source_images.blobs.find(outfit.character_snapshot.fetch("source_blob_id")))
      end
      plan.update!(status: "preparing")
    end
    queue_outfits(plan)
  rescue StandardError => error
    raise unless claimed
    plan.fail!(**BookWardrobeFailure.details(error, stage: stage))
  end

  def self.queue_outfits(plan)
    return unless plan.current?
    plan.book_outfits.where(status: "pending").find_each { |outfit| GenerateBookOutfitJob.perform_later(outfit.id) }
    BookWardrobeDispatch.call(plan)
  end
end
