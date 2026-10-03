require "net/http"

module HealthChecks
  class Openai < Base
    ENDPOINT = URI("https://api.openai.com/v1/models")

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

    def initialize(access_token: ENV["OPENAI_ACCESS_TOKEN"], transport: nil, **options)
      super(**options)
      @access_token = access_token
      @transport = transport || HttpTransport.new
    end

    def call
      start_check
      if @access_token.blank?
        return result(name: "openai", status: "not_configured", message: I18n.t("admin.health.messages.openai_missing"))
      end

      response = @transport.call(
        uri: ENDPOINT,
        headers: { "Authorization" => "Bearer #{@access_token}" },
        open_timeout: 3,
        read_timeout: 5
      )

      case response.code.to_i
      when 200..299
        result(name: "openai", status: "connected", message: I18n.t("admin.health.messages.openai_connected"))
      when 401, 403
        result(name: "openai", status: "failed", message: I18n.t("admin.health.messages.openai_forbidden"))
      else
        result(name: "openai", status: "failed", message: I18n.t("admin.health.messages.openai_unexpected"))
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      result(name: "openai", status: "failed", message: I18n.t("admin.health.messages.openai_timeout"))
    rescue StandardError
      result(name: "openai", status: "failed", message: I18n.t("admin.health.messages.openai_unreachable"))
    end
  end
end
