class CreatePages < ActiveRecord::Migration[7.0]
  def change
    create_table :pages do |t|
      t.string :image_description
      t.string :text
      t.references :book, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
