class ChangeRoleToRolesOnCharacters < ActiveRecord::Migration[8.0]
  def change
    remove_column :characters, :role, :string
    add_column :characters, :roles, :json, null: false, default: []
  end
end
