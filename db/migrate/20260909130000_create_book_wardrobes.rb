class CreateBookWardrobes < ActiveRecord::Migration[8.0]
  def change
    create_table :book_wardrobe_plans do |t|
      t.references :book, null: false, foreign_key: true
      t.integer :generation_attempt, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :story, null: false, default: []
      t.jsonb :character_snapshots, null: false, default: []
      t.jsonb :failure, null: false, default: {}
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :book_wardrobe_plans, [:book_id, :generation_attempt], unique: true

    create_table :book_outfits do |t|
      t.references :book_wardrobe_plan, null: false, foreign_key: true
      t.bigint :character_id, null: false
      t.string :outfit_key, null: false
      t.text :description, null: false
      t.jsonb :page_numbers, null: false, default: []
      t.jsonb :character_snapshot, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.jsonb :generation_metadata, null: false, default: {}
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :book_outfits, [:book_wardrobe_plan_id, :character_id, :outfit_key], unique: true, name: "index_book_outfits_unique_identity"

    add_reference :pages, :book_wardrobe_plan, foreign_key: true
    add_column :pages, :story_position, :integer
    add_index :pages, [:book_id, :generation_attempt, :story_position], unique: true, name: "index_pages_unique_story_position"
  end
end
