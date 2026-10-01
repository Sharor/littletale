# frozen_string_literal: true

class AddBlankPageCountToPrintOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :print_orders, :blank_page_count, :integer
  end
end
