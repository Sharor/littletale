# frozen_string_literal: true

module Lulu
  class ArtifactUrl
    EXPIRY = 6.hours
    KINDS = %w[interior cover].freeze

    def self.for(order:, kind:)
      kind = kind.to_s
      raise ArgumentError, "Unsupported print artifact." unless KINDS.include?(kind)
      raise ArgumentError, "Print artifacts are not current." unless order.artifacts_current?
      raise ConfigurationError, "A public HTTPS Lulu asset host is not configured." unless Configuration.asset_host_ready?

      payload = { order_id: order.id, revision: order.content_revision, kind: }
      token = verifier.generate(payload, expires_in: EXPIRY)
      path = Rails.application.routes.url_helpers.print_order_artifact_path(token:, kind:)
      URI.join("#{Configuration.asset_host}/", path.delete_prefix("/")).to_s
    end

    def self.verify(token)
      verifier.verify(token).deep_symbolize_keys
    end

    def self.verifier
      Rails.application.message_verifier("lulu-artifact")
    end
    private_class_method :verifier

    class ConfigurationError < StandardError; end
  end
end
