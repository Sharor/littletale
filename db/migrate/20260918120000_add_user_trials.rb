class AddUserTrials < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :trial_started_at, :datetime
    add_column :users, :trial_expires_at, :datetime

    create_table :trial_book_reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: true, index: false, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "held"
      t.datetime :released_at
      t.references :released_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :release_reason

      t.timestamps
    end

    add_index :trial_book_reservations, :book_id,
      unique: true,
      where: "status = 'held'",
      name: "index_held_trial_reservation_per_book"
    add_index :trial_book_reservations, [ :user_id, :status ]
  end
end
