class AddIllustrationToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_reference :illustrations, :character, null: true, foreign_key:  { on_delete: :cascade }
  end
end
