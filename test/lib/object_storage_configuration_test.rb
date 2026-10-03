require "test_helper"

class ObjectStorageConfigurationTest < ActiveSupport::TestCase
  test "prefers generic S3-compatible settings" do
    configuration = ObjectStorageConfiguration.from_env({
      "OBJECT_STORAGE_ACCESS_KEY" => "generic-key",
      "OBJECT_STORAGE_SECRET_KEY" => "generic-secret",
      "OBJECT_STORAGE_BUCKET" => "generic-bucket",
      "OBJECT_STORAGE_ENDPOINT" => "https://objects.example.com",
      "OBJECT_STORAGE_REGION" => "eu-north-1",
      "OBJECT_STORAGE_FORCE_PATH_STYLE" => "false",
      "MINIO_ACCESS_KEY" => "legacy-key",
      "MINIO_SECRET_KEY" => "legacy-secret",
      "MINIO_BUCKET" => "legacy-bucket",
      "MINIO_ENDPOINT" => "https://minio.example.com"
    })

    assert_equal "generic-key", configuration.access_key_id
    assert_equal "generic-secret", configuration.secret_access_key
    assert_equal "generic-bucket", configuration.bucket
    assert_equal "https://objects.example.com", configuration.endpoint
    assert_equal "eu-north-1", configuration.region
    assert_not configuration.force_path_style?
    assert configuration.configured?
  end

  test "falls back to existing MinIO settings" do
    configuration = ObjectStorageConfiguration.from_env({
      "MINIO_ACCESS_KEY" => "legacy-key",
      "MINIO_SECRET_KEY" => "legacy-secret",
      "MINIO_BUCKET" => "legacy-bucket",
      "MINIO_ENDPOINT" => "https://minio.example.com"
    })

    assert_equal "legacy-key", configuration.access_key_id
    assert_equal "legacy-secret", configuration.secret_access_key
    assert_equal "legacy-bucket", configuration.bucket
    assert_equal "https://minio.example.com", configuration.endpoint
    assert_equal "us-east-1", configuration.region
    assert configuration.force_path_style?
    assert configuration.configured?
  end

  test "reports missing required settings without exposing values" do
    configuration = ObjectStorageConfiguration.from_env({
      "OBJECT_STORAGE_ENDPOINT" => "https://objects.example.com"
    })

    assert_not configuration.configured?
    assert_equal %w[OBJECT_STORAGE_ACCESS_KEY OBJECT_STORAGE_SECRET_KEY OBJECT_STORAGE_BUCKET],
      configuration.missing_settings
  end

  test "uses Active Model boolean semantics for path-style addressing" do
    %w[0 f false off].each do |value|
      configuration = ObjectStorageConfiguration.from_env({ "OBJECT_STORAGE_FORCE_PATH_STYLE" => value })
      assert_not configuration.force_path_style?, "expected #{value.inspect} to disable path-style addressing"
    end

    configuration = ObjectStorageConfiguration.from_env({ "OBJECT_STORAGE_FORCE_PATH_STYLE" => "no" })
    assert configuration.force_path_style?
  end
end
