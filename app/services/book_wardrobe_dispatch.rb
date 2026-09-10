# frozen_string_literal: true

class BookWardrobeDispatch
  def self.call(plan)
    book = plan.book
    book.with_lock do
      return unless plan.generation_attempt == book.generation_attempt
      plan.reload
      return unless %w[preparing ready].include?(plan.status)
      outfits = plan.book_outfits.to_a
      return unless outfits.all? { |outfit| outfit.status == "ready" && outfit.image.attached? }
      plan.update!(status: "ready") unless plan.ready?
      plan.story.each_with_index do |data, index|
        page = book.pages.find_or_create_by!(generation_attempt: plan.generation_attempt, story_position: index + 1) do |record|
          record.text = data.fetch("story")
          record.book_wardrobe_plan = plan
        end
        page.create_illustration!(original_description: data.fetch("image")) unless page.illustration
      end
    end
    book.current_pages.each do |page|
      next if page.illustration.original_image.present? || PageIllustrationGeneration.state(page.illustration).present?
      GeneratePageJob.perform_later(book.id,
        { "wardrobe_plan_id" => plan.id, "position" => page.story_position }, plan.generation_attempt)
    end
    book.reload.send(:broadcast_generation_state)
  end
end
