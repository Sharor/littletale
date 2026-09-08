class GenerateImageJob < ApplicationJob
  queue_as :default

  # Ignore the old prompt: screen an immutable snapshot of current inputs.
  def perform(character_id, character_description = nil)
    Character.find_by(id: character_id)&.setup_illustration
  end
end
