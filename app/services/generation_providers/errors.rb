# frozen_string_literal: true

module GenerationProviders
  class InvalidResponse < StandardError; end

  class ContentRejected < Faraday::BadRequestError
    def initialize(message = "The provider rejected the content", response: {})
      super(message, response)
    end
  end
end
