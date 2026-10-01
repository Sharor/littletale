# frozen_string_literal: true

class AddCheckoutRevisionToPrintOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :print_orders, :checkout_revision, :integer, null: false, default: 1
  end
end
