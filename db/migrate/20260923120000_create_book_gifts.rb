# frozen_string_literal: true

class CreateBookGifts < ActiveRecord::Migration[8.0]
  def change
    create_table :book_gifts do |t|
      t.references :source_book, foreign_key: { to_table: :books, on_delete: :nullify }
      t.references :sender, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :recipient, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :recipient_name, null: false
      t.string :recipient_email, null: false
      t.string :sender_callname, null: false
      t.text :message, null: false
      t.string :language, null: false
      t.string :title, null: false
      t.string :token_digest, null: false
      t.datetime :claimed_at
      t.string :delivery_status, null: false, default: "not_sent"
      t.text :delivery_error
      t.datetime :email_queued_at
      t.datetime :delivered_at

      t.timestamps
    end
    add_index :book_gifts, :token_digest, unique: true
    add_index :book_gifts, [ :recipient_id, :claimed_at ]

    create_table :gift_pages do |t|
      t.references :book_gift, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :text, null: false

      t.timestamps
    end
    add_index :gift_pages, [ :book_gift_id, :position ], unique: true
  end
end
