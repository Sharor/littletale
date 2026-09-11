require "test_helper"

class CableTest < ActiveSupport::TestCase
  test "development generation workers share cable messages with the web process" do
    cable = Rails.application.config_for(:cable, env: "development")
    assert_equal "solid_cable", cable[:adapter],
      "Character and book jobs run outside the web process and cannot use async broadcasts"

    role = cable.dig(:connects_to, :database, :writing)
    database = ActiveRecord::Base.configurations.configs_for(env_name: "development", name: role.to_s)
    assert_not_nil database, "The shared cable database must be prepared with the development databases"
    assert_equal Rails.root.join("storage/development_cable.sqlite3").to_s, database.database
    assert_equal "db/cable_migrate", database.migrations_paths
  end
end
