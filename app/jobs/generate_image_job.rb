class GenerateImageJob < ApplicationJob
  queue_as :default

  def perform(character_id, character_description)
    Rails.logger.warn("Running job GenerateImageJob")
    character = Character.find(character_id)

    character.in_progress!
    Illustration.where(character_id: character_id).first_or_initialize.generate_single_character(character_description)
    character.completed!
  end
end
