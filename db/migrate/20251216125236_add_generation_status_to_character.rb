class AddGenerationStatusToCharacter < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :generation_status, :integer, default: 0
  end
end
