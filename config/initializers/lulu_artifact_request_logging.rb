# frozen_string_literal: true

require Rails.root.join("lib/lulu/artifact_request_logger")

Rails.application.config.middleware.swap(
  Rails::Rack::Logger,
  Lulu::ArtifactRequestLogger,
  Rails.application.config.log_tags
)
