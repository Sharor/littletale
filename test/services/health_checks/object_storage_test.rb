require "test_helper"
require "aws-sdk-s3"

class HealthChecksObjectStorageTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:response) do
    attr_reader :head_bucket_calls

    def head_bucket(bucket:)
      @head_bucket_calls = Array(@head_bucket_calls) << bucket
      raise response if response.is_a?(Exception)

      response
    end
  end

  test "reports a connected bucket after one read-only request" do
    configuration = configured_storage
    client = FakeClient.new(Object.new)
    received_options = nil
    factory = ->(**options) { received_options = options; client }

    result = HealthChecks::ObjectStorage.new(
      configuration: configuration,
      client_factory: factory,
      wall_clock: -> { Time.zone.parse("2026-10-03 10:00:00") },
      monotonic_clock: sequence_clock(4.0, 4.025)
    ).call

    assert_equal "object_storage", result.name
    assert_equal "connected", result.status
    assert_equal "Connection and bucket access confirmed.", result.message
    assert_equal "2026-10-03T10:00:00Z", result.checked_at
    assert_equal 25, result.duration_ms
    assert_equal [ "stories" ], client.head_bucket_calls
    assert_equal 0, received_options.fetch(:retry_limit)
    assert_equal 3, received_options.fetch(:http_open_timeout)
    assert_equal 5, received_options.fetch(:http_read_timeout)
  end

  test "reports missing settings without constructing a client" do
    configuration = ObjectStorageConfiguration.from_env({})
    factory = ->(**) { flunk "client must not be constructed" }

    result = HealthChecks::ObjectStorage.new(configuration: configuration, client_factory: factory).call

    assert_equal "not_configured", result.status
    assert_equal "Missing OBJECT_STORAGE_ACCESS_KEY, OBJECT_STORAGE_SECRET_KEY, and OBJECT_STORAGE_BUCKET.", result.message
  end

  test "reports timeouts without retrying or leaking provider details" do
    client = FakeClient.new(Seahorse::Client::NetworkingError.new(Net::ReadTimeout.new("secret endpoint")))

    result = HealthChecks::ObjectStorage.new(
      configuration: configured_storage,
      client_factory: ->(**) { client }
    ).call

    assert_equal "failed", result.status
    assert_equal "The object storage request timed out.", result.message
    assert_equal [ "stories" ], client.head_bucket_calls
    assert_no_match "secret", result.message
  end

  test "reports denied bucket access without provider details" do
    error = Aws::S3::Errors::Forbidden.new(nil, "secret provider response")
    client = FakeClient.new(error)

    result = HealthChecks::ObjectStorage.new(
      configuration: configured_storage,
      client_factory: ->(**) { client }
    ).call

    assert_equal "failed", result.status
    assert_equal "The configured credentials cannot access the object storage bucket.", result.message
    assert_no_match "secret", result.message
  end

  private
    def configured_storage
      ObjectStorageConfiguration.from_env({
        "OBJECT_STORAGE_ACCESS_KEY" => "access-key",
        "OBJECT_STORAGE_SECRET_KEY" => "secret-key",
        "OBJECT_STORAGE_BUCKET" => "stories",
        "OBJECT_STORAGE_ENDPOINT" => "https://objects.example.com"
      })
    end

    def sequence_clock(*values)
      -> { values.shift || values.last }
    end
end
