class ObjectStorageConfiguration
  REQUIRED_SETTINGS = {
    access_key_id: %w[OBJECT_STORAGE_ACCESS_KEY MINIO_ACCESS_KEY],
    secret_access_key: %w[OBJECT_STORAGE_SECRET_KEY MINIO_SECRET_KEY],
    bucket: %w[OBJECT_STORAGE_BUCKET MINIO_BUCKET]
  }.freeze

  attr_reader :access_key_id, :secret_access_key, :bucket, :endpoint, :region

  def self.from_env(env = ENV)
    new(
      access_key_id: first_present(env, *REQUIRED_SETTINGS.fetch(:access_key_id)),
      secret_access_key: first_present(env, *REQUIRED_SETTINGS.fetch(:secret_access_key)),
      bucket: first_present(env, *REQUIRED_SETTINGS.fetch(:bucket)),
      endpoint: first_present(env, "OBJECT_STORAGE_ENDPOINT", "MINIO_ENDPOINT"),
      region: first_present(env, "OBJECT_STORAGE_REGION") || "us-east-1",
      force_path_style: parse_boolean(first_present(env, "OBJECT_STORAGE_FORCE_PATH_STYLE"), default: true)
    )
  end

  def self.first_present(env, *keys)
    keys.filter_map { |key| env[key].presence }.first
  end
  private_class_method :first_present

  def self.parse_boolean(value, default:)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end
  private_class_method :parse_boolean

  def initialize(access_key_id:, secret_access_key:, bucket:, endpoint:, region:, force_path_style:)
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @bucket = bucket
    @endpoint = endpoint
    @region = region
    @force_path_style = force_path_style
  end

  def force_path_style?
    @force_path_style
  end

  def configured?
    missing_settings.empty?
  end

  def missing_settings
    REQUIRED_SETTINGS.filter_map do |attribute, names|
      names.first if public_send(attribute).blank?
    end
  end
end
