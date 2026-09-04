class CreateIllustrations < ActiveRecord::Migration[8.0]
  def change
    create_table :illustrations do |t|
      t.string :prompt
      t.string :image_url
      t.string :original_image
      t.string :original_description
      t.references :page, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
