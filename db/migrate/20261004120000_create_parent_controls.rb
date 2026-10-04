# frozen_string_literal: true

class CreateParentControls < ActiveRecord::Migration[8.0]
  def change
    create_table :parent_controls do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :mode, null: false, default: "approval_required"
      t.integer :daily_book_limit, null: false, default: 1
      t.string :time_zone, null: false, default: "UTC"
      t.string :pin_digest, null: false

      t.timestamps
    end

    create_table :parental_generation_requests do |t|
      t.references :parent_control, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :generatable, polymorphic: true, null: false
      t.string :kind, null: false
      t.string :policy_mode, null: false
      t.string :request_key, null: false
      t.string :status, null: false, default: "pending"
      t.date :reserved_on
      t.datetime :decided_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :parental_generation_requests,
      %i[generatable_type generatable_id request_key],
      unique: true,
      where: "status IN ('pending', 'approved')",
      name: "index_active_parental_generation_requests"
    add_index :parental_generation_requests,
      %i[parent_control_id kind status completed_at],
      name: "index_parental_generation_usage"
  end
end
