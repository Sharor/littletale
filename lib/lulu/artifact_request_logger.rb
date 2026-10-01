# frozen_string_literal: true

require "rails/rack/logger"

module Lulu
  class ArtifactRequestLogger < Rails::Rack::Logger
    ARTIFACT_PATH = %r{\A/lulu-files/[^/]+/(interior|cover)\.pdf\z}

    private

    def started_request_message(request)
      match = ARTIFACT_PATH.match(request.path)
      return super unless match

      request.instance_variable_set(:@filtered_path, "/lulu-files/[FILTERED]/#{match[1]}.pdf")
      super
    end
  end
end
