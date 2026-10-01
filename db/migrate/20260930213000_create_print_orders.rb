# frozen_string_literal: true

class CreatePrintOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :print_orders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :source_book, foreign_key: { to_table: :books, on_delete: :nullify }
      t.string :title, null: false
      t.string :language, null: false
      t.string :workflow_state, null: false, default: "draft"
      t.integer :step, null: false, default: 1
      t.string :pod_package_id, null: false
      t.integer :content_revision, null: false, default: 1
      t.integer :artifacts_revision
      t.integer :interior_page_count
      t.string :recipient_name
      t.string :street1
      t.string :street2
      t.string :city
      t.string :postcode
      t.string :country_code
      t.string :state_code
      t.string :recipient_email
      t.string :phone_number
      t.string :shipping_option
      t.json :shipping_options, null: false, default: []
      t.json :quote, null: false, default: {}
      t.integer :quote_revision
      t.datetime :quoted_at
      t.string :validation_state, null: false, default: "not_started"
      t.json :validation_details, null: false, default: {}
      t.json :cover_dimensions, null: false, default: {}
      t.string :submission_uuid
      t.string :lulu_print_job_id
      t.string :provider_status
      t.text :failure_message
      t.datetime :submitted_at
      t.datetime :submission_uncertain_at
      t.datetime :last_status_checked_at

      t.timestamps
    end
    add_index :print_orders, :submission_uuid, unique: true
    add_index :print_orders, :lulu_print_job_id, unique: true
    add_index :print_orders, [ :user_id, :created_at ]

    create_table :print_order_pages do |t|
      t.references :print_order, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :text, null: false

      t.timestamps
    end
    add_index :print_order_pages, [ :print_order_id, :position ], unique: true
  end
end
