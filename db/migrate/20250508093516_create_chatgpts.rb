class CreateChatgpts < ActiveRecord::Migration[7.0]
  def change
    create_table :chatgpts do |t|
      t.text :prompt
      t.text :answer
      t.integer :max_tokens
      t.integer :audience
      t.text :reason_for_termination
      t.text :usage
      t.references :book, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
