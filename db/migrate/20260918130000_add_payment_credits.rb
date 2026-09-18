class AddPaymentCredits < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :stripe_customer_id, :string
    add_index :users, :stripe_customer_id, unique: true

    create_table :book_purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :product_id, null: false
      t.string :price_id
      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.string :stripe_customer_id
      t.string :idempotency_key, null: false
      t.integer :amount_total
      t.string :currency
      t.boolean :livemode, null: false, default: false
      t.datetime :paid_at
      t.text :failure_reason
      t.timestamps
    end
    add_index :book_purchases, :idempotency_key, unique: true
    add_index :book_purchases, :stripe_checkout_session_id, unique: true
    add_index :book_purchases, :stripe_payment_intent_id, unique: true

    create_table :book_credits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book_purchase, null: false, index: false, foreign_key: true
      t.string :status, null: false, default: "available"
      t.timestamps
    end
    add_index :book_credits, :book_purchase_id, unique: true
    add_index :book_credits, [ :user_id, :status ]

    create_table :character_credits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book_purchase, null: false, foreign_key: true
      t.integer :ordinal, null: false
      t.string :status, null: false, default: "available"
      t.timestamps
    end
    add_index :character_credits, [ :book_purchase_id, :ordinal ], unique: true
    add_index :character_credits, [ :user_id, :status ]

    create_table :book_credit_reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book_credit, null: false, foreign_key: true
      t.references :book, null: true, index: false, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "held"
      t.datetime :released_at
      t.references :released_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :release_reason
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :book_credit_reservations, :book_id, unique: true,
      where: "status = 'held'", name: "index_held_book_credit_reservation_per_book"
    add_index :book_credit_reservations, :book_credit_id, unique: true,
      where: "status = 'held'", name: "index_held_reservation_per_book_credit"
    add_index :book_credit_reservations, [ :user_id, :status ]

    create_table :character_credit_reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :character_credit, null: false, foreign_key: true
      t.references :character_image_request, null: true, index: false, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "held"
      t.datetime :released_at
      t.references :released_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :release_reason
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :character_credit_reservations, :character_image_request_id, unique: true,
      where: "status = 'held'", name: "index_held_character_credit_reservation_per_request"
    add_index :character_credit_reservations, :character_credit_id, unique: true,
      where: "status = 'held'", name: "index_held_reservation_per_character_credit"
    add_index :character_credit_reservations, [ :user_id, :status ]

    create_table :stripe_events do |t|
      t.string :stripe_event_id, null: false
      t.string :event_type, null: false
      t.string :stripe_object_id
      t.datetime :processed_at, null: false
      t.timestamps
    end
    add_index :stripe_events, :stripe_event_id, unique: true
    add_index :stripe_events, [ :event_type, :stripe_object_id ], unique: true,
      where: "stripe_object_id IS NOT NULL", name: "index_stripe_events_on_type_and_object"
  end
end
