class CreateJoinTableBookCharacter < ActiveRecord::Migration[8.0]
  def change
    create_join_table :books, :characters do |t|
      t.index [ :book_id, :character_id ]
      t.index [ :character_id, :book_id ]
    end
  end
end
