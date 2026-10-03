require "test_helper"
require "erb"
require "yaml"

class StorageConfigurationTest < ActiveSupport::TestCase
  test "S3-compatible services use the same path-style boolean values as the shared configuration" do
    assert_equal false, force_path_style_from_storage_yml("f")
    assert_equal true, force_path_style_from_storage_yml("no")
  end

  private
    def force_path_style_from_storage_yml(value)
      previous = ENV["OBJECT_STORAGE_FORCE_PATH_STYLE"]
      ENV["OBJECT_STORAGE_FORCE_PATH_STYLE"] = value
      yaml = ERB.new(Rails.root.join("config/storage.yml").read).result
      YAML.safe_load(yaml).dig("object_storage", "force_path_style")
    ensure
      ENV["OBJECT_STORAGE_FORCE_PATH_STYLE"] = previous
    end
end
