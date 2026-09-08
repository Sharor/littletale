class CartoonImageJob < ApplicationJob
  queue_as :default

  # Compatibility for jobs queued before screening was introduced.
  def perform(character_id, frontend_char_id = nil)
    character = Character.find_by(id: character_id)
    character&.setup_illustration(frontend_char_id)
  end
end
