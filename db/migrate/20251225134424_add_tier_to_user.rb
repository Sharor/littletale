class AddTierToUser < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :tier, :text
  end
end
