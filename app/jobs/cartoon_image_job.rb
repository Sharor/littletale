class CartoonImageJob < ApplicationJob
  queue_as :default

  def perform(character_id, frontend_char_id)
    character = Character.find(character_id)

    character.update!(generation_status: :in_progress)
    p "Performing for #{character_id}"
    Illustration.where(character_id: character_id).first_or_initialize.cartoonify([ character ])



    # Broadcast to frontend when finished
    target_id = "illustration_section_#{character.id}"
    Turbo::StreamsChannel.broadcast_replace_to(
      "character_#{character.id}_updates",
      target: target_id,
      partial: "illustrations/illustration",
      locals: { character: character }
    )

    p "Finished for #{character_id}"
    character.completed!
  end
end
