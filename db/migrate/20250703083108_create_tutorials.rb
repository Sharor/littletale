class CreateTutorials < ActiveRecord::Migration[8.0]
  def change
    create_table :tutorials do |t|
      t.boolean :eula
      t.boolean :terms
      t.boolean :tutorial_complete
      t.references :user, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
