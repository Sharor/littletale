class CreateBooks < ActiveRecord::Migration[7.0]
  def change
    create_table :books do |t|
      t.string :name
      t.string :plot # user_prompt
      t.integer :page_count
      t.string :text_context
      t.references :user, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
