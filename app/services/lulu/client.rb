# frozen_string_literal: true

require "base64"
require "faraday"
require "json"

module Lulu
  class Client
    TOKEN_PATH = "/auth/realms/glasstree/protocol/openid-connect/token"
    TOKEN_EXPIRY_SKEW = 30.seconds

    class ConfigurationError < StandardError; end

    class RequestError < StandardError
      SENSITIVE_KEYS = %w[
        access_token authorization city client_secret contact_email country country_code email name password phone_number
        postcode recipient_email recipient_name secret source_url state state_code street1 street2 token
      ].freeze
      MAX_DESCRIPTION_LENGTH = 1_000
      attr_reader :status, :details

      def initialize(status:, details:)
        @status = status
        @details = self.class.sanitize(details)
        super("Lulu request failed (#{status}): #{self.class.describe(@details)}")
      end

      def self.describe(details)
        description = case details
        when Hash
          details.flat_map do |key, value|
            values = value.is_a?(Array) ? value : [ value ]
            values.map { |item| "#{key}: #{item.is_a?(Hash) ? describe(item) : item}" }
          end.join(", ")
        when Array
          details.map { |item| item.is_a?(Hash) ? describe(item) : item }.join(", ")
        else
          details.to_s
        end
        (description.presence || "No provider details were returned.").truncate(MAX_DESCRIPTION_LENGTH)
      end

      def self.sanitize(value, key = nil)
        return "[FILTERED]" if key && SENSITIVE_KEYS.include?(key.to_s.downcase)

        case value
        when Hash
          value.to_h { |nested_key, nested_value| [ nested_key, sanitize(nested_value, nested_key) ] }
        when Array
          value.map { |item| sanitize(item) }
        when String
          value
            .gsub(%r{https?://[^\s"'<>\]]+}, "[FILTERED]")
            .gsub(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i, "[FILTERED]")
            .gsub(/(?<!\w)\+?\d[\d\s().\-]{6,}\d/, "[FILTERED]")
            .truncate(MAX_DESCRIPTION_LENGTH)
        else
          value
        end
      end
    end

    def initialize(
      client_id: Configuration.client_id,
      client_secret: Configuration.client_secret,
      base_url: Configuration.base_url,
      clock: -> { Time.current }
    )
      raise ConfigurationError, "Lulu sandbox credentials are not configured." if client_id.blank? || client_secret.blank?
      raise ConfigurationError, "Only the Lulu sandbox host is allowed." unless base_url == Configuration::SANDBOX_BASE_URL

      @client_id = client_id
      @client_secret = client_secret
      @clock = clock
      @connection = Faraday.new(url: base_url) do |faraday|
        faraday.options.open_timeout = 5
        faraday.options.timeout = 20
      end
    end

    def create_interior_validation(source_url:, pod_package_id:)
      post("/validate-interior/", source_url:, pod_package_id:)
    end

    def interior_validation(id)
      get("/validate-interior/#{Integer(id)}/")
    end

    def cover_dimensions(pod_package_id:, interior_page_count:)
      post("/cover-dimensions/", pod_package_id:, interior_page_count:, unit: "inch")
    end

    def create_cover_validation(source_url:, pod_package_id:, interior_page_count:)
      post("/validate-cover/", source_url:, pod_package_id:, interior_page_count:)
    end

    def cover_validation(id)
      get("/validate-cover/#{Integer(id)}/")
    end

    def shipping_options(address:, line_items:, currency:)
      post("/shipping-options/", {
        currency:,
        line_items:,
        shipping_address: {
          name: address[:name], street1: address[:street1], street2: address[:street2], city: address[:city],
          postcode: address[:postcode], country: address[:country_code], state: address[:state_code],
          phone_number: address[:phone_number]
        }
      })
    end

    def cost_calculation(address:, line_items:, shipping_option:)
      post("/print-job-cost-calculations/", {
        shipping_option:,
        line_items:,
        shipping_address: {
          name: address[:name], street1: address[:street1], street2: address[:street2], city: address[:city],
          postcode: address[:postcode], country_code: address[:country_code], state_code: address[:state_code],
          email: address[:email], phone_number: address[:phone_number]
        }
      })
    end

    def create_print_job(**payload)
      post("/print-jobs/", payload)
    end

    def find_print_job_by_external_id(external_id)
      response = get("/print-jobs/", search: external_id, page_size: 100, exclude_line_items: true)
      Array(response["results"]).find { |job| job["external_id"] == external_id }
    end

    def print_job_status(id)
      get("/print-jobs/#{id}/status/")
    end

    private

    def get(path, query = nil)
      request(:get, path, query:)
    end

    def post(path, body)
      request(:post, path, body:)
    end

    def request(method, path, body: nil, query: nil, retry_auth: true)
      response = @connection.public_send(method, path) do |request|
        request.headers["Authorization"] = "Bearer #{access_token}"
        request.headers["Cache-Control"] = "no-cache"
        request.params.update(query) if query
        if body
          request.headers["Content-Type"] = "application/json"
          request.body = JSON.generate(body)
        end
      end

      if response.status == 401 && retry_auth
        clear_token
        return request(method, path, body:, query:, retry_auth: false)
      end

      parse_response(response)
    rescue Faraday::Error
      raise RequestError.new(status: 0, details: "The Lulu sandbox did not respond.")
    end

    def access_token
      return @access_token if @access_token.present? && @token_expires_at > @clock.call

      response = @connection.post(TOKEN_PATH) do |request|
        request.headers["Authorization"] = "Basic #{Base64.strict_encode64("#{@client_id}:#{@client_secret}")}"
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(grant_type: "client_credentials")
      end
      payload = parse_response(response)
      @access_token = payload.fetch("access_token")
      @token_expires_at = @clock.call + payload.fetch("expires_in").to_i.seconds - TOKEN_EXPIRY_SKEW
      @access_token
    end

    def clear_token
      @access_token = nil
      @token_expires_at = nil
    end

    def parse_response(response)
      payload = response.body.present? ? JSON.parse(response.body) : {}
      return payload if response.status.between?(200, 299)

      raise RequestError.new(status: response.status, details: payload)
    rescue JSON::ParserError
      raise RequestError.new(status: response.status, details: "The provider returned an unreadable response.")
    end
  end
end
