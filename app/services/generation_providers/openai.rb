# frozen_string_literal: true

module GenerationProviders
  class Openai
    def initialize(access_token: ENV.fetch("OPENAI_ACCESS_TOKEN", nil))
      @client = OpenAI::Client.new(access_token: access_token)
    end

    def model_for(_capability, parameters)
      parameters[:model].to_s
    end

    def chat(parameters:)
      @client.chat(parameters: parameters)
    end

    def moderations(parameters:)
      @client.moderations(parameters: parameters)
    end

    def generate(parameters:)
      @client.images.generate(parameters: parameters)
    end

    def edit(parameters:)
      @client.images.edit(parameters: parameters)
    end
  end
end
