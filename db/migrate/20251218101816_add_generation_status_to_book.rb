class AddGenerationStatusToBook < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :generation_status, :integer, default: 0
  end
end
