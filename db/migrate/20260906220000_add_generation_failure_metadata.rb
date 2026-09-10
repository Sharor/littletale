class AddGenerationFailureMetadata < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :generation_failure, :json, null: false, default: {}
    add_column :books, :generation_failed_at, :datetime
    add_column :illustrations, :generation_metadata, :json, null: false, default: {}
  end
end
