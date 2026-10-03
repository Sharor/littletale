require Rails.root.join("lib/object_storage_configuration")

CarrierWave.configure do |config|
  if Rails.env.production?
    storage = ObjectStorageConfiguration.from_env
    config.fog_credentials = {
      provider:              "AWS",
      aws_access_key_id:     storage.access_key_id || "dummy",
      aws_secret_access_key: storage.secret_access_key || "dummy",
      region:                storage.region,
      path_style:            storage.force_path_style?
    }.tap do |credentials|
      credentials[:endpoint] = storage.endpoint if storage.endpoint.present?
    end
    config.fog_directory  = storage.bucket || "dummy"
    config.fog_public     = false
    config.storage        = :fog
  elsif Rails.env.test?
    config.storage = :file
    config.enable_processing = false
    config.root = -> { Rails.root.join("tmp/carrierwave/#{Process.pid}") }
  else
    config.storage = :file
    config.enable_processing = Rails.env.development?
  end
end
