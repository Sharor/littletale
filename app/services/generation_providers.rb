# frozen_string_literal: true

require_relative "generation_providers/errors"

module GenerationProviders
  def self.client(operation:)
    Client.new(operation: operation)
  end

  def self.adapter_for(provider)
    case provider
    when "openai" then Openai.new
    when "gemini" then Gemini.new
    else raise ArgumentError, "Unknown generation provider"
    end
  end
end
