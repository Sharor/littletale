class CreateCharacters < ActiveRecord::Migration[7.0]
  def change
    create_table :characters do |t|
      t.string :name
      t.integer :age
      t.string :gender
      t.string :hair_color
      t.string :hair_style
      t.string :eye_color
      t.string :role
      t.references :user, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
