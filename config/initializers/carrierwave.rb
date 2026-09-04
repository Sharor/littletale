CarrierWave.configure do |config|
  if Rails.env.production?
    config.fog_credentials = {
      provider:              "AWS",
      aws_access_key_id:     ENV["MINIO_ACCESS_KEY"] || "dummy",
      aws_secret_access_key: ENV["MINIO_SECRET_KEY"] || "dummy",
      region:                "us-east-1" || "dummy",
      endpoint:              ENV["MINIO_ENDPOINT"],
      path_style:            true # Required for MinIO
    }
    config.fog_directory  = ENV["MINIO_BUCKET"]|| "dummy"
    config.fog_public     = false
    config.storage        = :fog
  else
    config.storage = :file
    config.enable_processing = Rails.env.development?
  end
end
