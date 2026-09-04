class AddEthnicityToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :ethnicity, :string
  end
end
