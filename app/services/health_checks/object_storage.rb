require "aws-sdk-s3"

module HealthChecks
  class ObjectStorage < Base
    def initialize(configuration: ObjectStorageConfiguration.from_env,
      client_factory: ->(**options) { Aws::S3::Client.new(**options) }, **options)
      super(**options)
      @configuration = configuration
      @client_factory = client_factory
    end

    def call
      start_check
      return missing_configuration_result unless @configuration.configured?

      @client_factory.call(**client_options).head_bucket(bucket: @configuration.bucket)
      result(name: "object_storage", status: "connected", message: I18n.t("admin.health.messages.storage_connected"))
    rescue Seahorse::Client::NetworkingError => error
      message = I18n.t(timeout?(error) ? "admin.health.messages.storage_timeout" : "admin.health.messages.storage_unreachable")
      result(name: "object_storage", status: "failed", message: message)
    rescue Aws::S3::Errors::Forbidden
      result(name: "object_storage", status: "failed",
        message: I18n.t("admin.health.messages.storage_forbidden"))
    rescue Aws::S3::Errors::ServiceError
      result(name: "object_storage", status: "failed", message: I18n.t("admin.health.messages.storage_rejected"))
    rescue StandardError
      result(name: "object_storage", status: "failed", message: I18n.t("admin.health.messages.storage_failed"))
    end

    private
      def client_options
        {
          access_key_id: @configuration.access_key_id,
          secret_access_key: @configuration.secret_access_key,
          region: @configuration.region,
          force_path_style: @configuration.force_path_style?,
          retry_limit: 0,
          http_open_timeout: 3,
          http_read_timeout: 5
        }.tap do |options|
          options[:endpoint] = @configuration.endpoint if @configuration.endpoint.present?
        end
      end

      def missing_configuration_result
        names = @configuration.missing_settings
        list = names.to_sentence
        result(name: "object_storage", status: "not_configured",
          message: I18n.t("admin.health.messages.storage_missing", settings: list))
      end

      def timeout?(error)
        original_error = error.respond_to?(:original_error) ? error.original_error : error.cause
        original_error.is_a?(Timeout::Error)
      end
  end
end
