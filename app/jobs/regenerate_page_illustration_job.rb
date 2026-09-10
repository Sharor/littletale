# frozen_string_literal: true

class RegeneratePageIllustrationJob < ApplicationJob
  queue_as :default

  def perform(illustration_id, token)
    illustration = Illustration.find_by(id: illustration_id)
    PageIllustrationGeneration.perform!(illustration, token) if illustration
  end
end
