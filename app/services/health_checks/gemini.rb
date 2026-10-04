# frozen_string_literal: true

require "cgi"
require "net/http"

module HealthChecks
  class Gemini < Base
    MODELS_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models"
    DEFAULT_MODEL = "gemini-3.8-flash"
    DEFAULT_IMAGE_MODEL = "gemini-3.1-flash-image"

    class HttpTransport
      def initialize(http_factory: ->(host, port) { Net::HTTP.new(host, port) })
        @http_factory = http_factory
      end

      def call(uri:, headers:, open_timeout:, read_timeout:)
        http = @http_factory.call(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.max_retries = 0
        request = Net::HTTP::Get.new(uri, headers)

        http.start { |connection| connection.request(request) }
      end
    end

    def initialize(api_key: ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_TEXT_MODEL", DEFAULT_MODEL),
      image_model: ENV.fetch("GEMINI_IMAGE_MODEL", DEFAULT_IMAGE_MODEL), transport: nil, **options)
      super(**options)
      @api_key = api_key
      @models = [
        model.to_s.delete_prefix("models/").presence || DEFAULT_MODEL,
        image_model.to_s.delete_prefix("models/").presence || DEFAULT_IMAGE_MODEL
      ].uniq
      @transport = transport || HttpTransport.new
    end

    def call
      start_check
      if @api_key.blank?
        return result(name: "gemini", status: "not_configured",
          message: I18n.t("admin.health.messages.gemini_missing"))
      end

      @models.each do |model|
        response = @transport.call(
          uri: URI("#{MODELS_ENDPOINT}/#{CGI.escape(model)}"),
          headers: { "x-goog-api-key" => @api_key },
          open_timeout: 3,
          read_timeout: 5
        )

        case response.code.to_i
        when 200..299
          next
        when 401, 403
          return result(name: "gemini", status: "failed",
            message: I18n.t("admin.health.messages.gemini_forbidden"))
        else
          return result(name: "gemini", status: "failed",
            message: I18n.t("admin.health.messages.gemini_unexpected"))
        end
      end

      result(name: "gemini", status: "connected", message: I18n.t("admin.health.messages.gemini_connected"))
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      result(name: "gemini", status: "failed", message: I18n.t("admin.health.messages.gemini_timeout"))
    rescue StandardError
      result(name: "gemini", status: "failed", message: I18n.t("admin.health.messages.gemini_unreachable"))
    end
  end
end
