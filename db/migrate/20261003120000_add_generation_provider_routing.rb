# frozen_string_literal: true

class AddGenerationProviderRouting < ActiveRecord::Migration[8.0]
  def change
    create_table :generation_provider_settings do |t|
      t.string :key, null: false, default: "global"
      t.string :mode, null: false, default: "openai"
      t.string :active_provider, null: false, default: "openai"
      t.datetime :automatic_window_started_at
      t.datetime :switched_at
      t.string :switch_reason
      t.timestamps
    end
    add_index :generation_provider_settings, :key, unique: true

    create_table :generation_provider_requests do |t|
      t.string :provider, null: false
      t.string :operation, null: false
      t.string :model, null: false
      t.string :outcome, null: false
      t.integer :http_status
      t.string :error_class
      t.string :external_request_id
      t.datetime :started_at, null: false
      t.datetime :finished_at, null: false
      t.timestamps
    end
    add_index :generation_provider_requests, [ :provider, :outcome, :started_at, :id ],
      name: "index_generation_provider_requests_for_failover"
  end
end
