class AddUserSubscriptions < ActiveRecord::Migration[8.0]
  def up
    create_table :user_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :product_id, null: false
      t.string :price_id
      t.string :stripe_subscription_id
      t.string :stripe_checkout_session_id
      t.string :stripe_customer_id
      t.string :idempotency_key, null: false
      t.boolean :livemode, null: false, default: false
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :ended_at
      t.text :checkout_url
      t.datetime :checkout_expires_at
      t.text :failure_reason
      t.timestamps
    end
    add_index :user_subscriptions, :idempotency_key, unique: true
    add_index :user_subscriptions, :stripe_subscription_id, unique: true
    add_index :user_subscriptions, :stripe_checkout_session_id, unique: true
    add_index :user_subscriptions, :user_id, unique: true,
      where: "status IN ('pending', 'active', 'past_due', 'unpaid')",
      name: "index_one_current_user_subscription"

    create_table :subscription_periods do |t|
      t.references :user_subscription, null: false, foreign_key: true
      t.string :stripe_invoice_id, null: false
      t.string :price_id, null: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.timestamps
    end
    add_index :subscription_periods, :stripe_invoice_id, unique: true
    add_index :subscription_periods, [ :user_subscription_id, :period_start ], unique: true

    change_column_null :book_credits, :book_purchase_id, true
    add_reference :book_credits, :subscription_period, null: true, foreign_key: true
    add_column :book_credits, :visible, :boolean, null: false, default: true
    add_column :book_credits, :expires_at, :datetime
    add_index :book_credits, [ :subscription_period_id, :id ],
      name: "index_book_credits_on_subscription_period_and_id"
    add_index :book_credits, [ :user_id, :visible, :status ],
      name: "index_book_credits_on_user_visibility_status"

    change_column_null :character_credits, :book_purchase_id, true
    add_reference :character_credits, :subscription_period, null: true, foreign_key: true
    add_column :character_credits, :visible, :boolean, null: false, default: true
    add_column :character_credits, :expires_at, :datetime
    add_index :character_credits, [ :subscription_period_id, :ordinal ], unique: true,
      where: "subscription_period_id IS NOT NULL",
      name: "index_character_credits_on_period_and_ordinal"
    add_index :character_credits, [ :user_id, :visible, :status ],
      name: "index_character_credits_on_user_visibility_status"

    remove_index :stripe_events, name: "index_stripe_events_on_type_and_object"
    add_index :stripe_events, [ :event_type, :stripe_object_id ],
      name: "index_stripe_events_on_type_and_object"
  end

  def down
    execute <<~SQL.squish
      DELETE FROM stripe_events
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM stripe_events
        WHERE stripe_object_id IS NOT NULL
        GROUP BY event_type, stripe_object_id
      )
      AND stripe_object_id IS NOT NULL
    SQL
    remove_index :stripe_events, name: "index_stripe_events_on_type_and_object"
    add_index :stripe_events, [ :event_type, :stripe_object_id ], unique: true,
      where: "stripe_object_id IS NOT NULL", name: "index_stripe_events_on_type_and_object"

    execute <<~SQL.squish
      DELETE FROM book_credit_reservations
      WHERE book_credit_id IN (
        SELECT id FROM book_credits WHERE subscription_period_id IS NOT NULL
      )
    SQL
    execute <<~SQL.squish
      DELETE FROM character_credit_reservations
      WHERE character_credit_id IN (
        SELECT id FROM character_credits WHERE subscription_period_id IS NOT NULL
      )
    SQL
    execute "DELETE FROM book_credits WHERE subscription_period_id IS NOT NULL"
    execute "DELETE FROM character_credits WHERE subscription_period_id IS NOT NULL"

    remove_index :character_credits, name: "index_character_credits_on_user_visibility_status"
    remove_index :character_credits, name: "index_character_credits_on_period_and_ordinal"
    remove_column :character_credits, :expires_at
    remove_column :character_credits, :visible
    remove_reference :character_credits, :subscription_period, foreign_key: true
    change_column_null :character_credits, :book_purchase_id, false

    remove_index :book_credits, name: "index_book_credits_on_user_visibility_status"
    remove_index :book_credits, name: "index_book_credits_on_subscription_period_and_id"
    remove_column :book_credits, :expires_at
    remove_column :book_credits, :visible
    remove_reference :book_credits, :subscription_period, foreign_key: true
    change_column_null :book_credits, :book_purchase_id, false

    drop_table :subscription_periods
    drop_table :user_subscriptions
  end
end
