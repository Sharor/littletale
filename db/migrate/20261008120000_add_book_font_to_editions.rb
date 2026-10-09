# frozen_string_literal: true

class AddBookFontToEditions < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :book_font, :string, default: "eb_garamond", null: false
    add_column :book_gifts, :book_font, :string, default: "eb_garamond", null: false
    add_column :print_orders, :book_font, :string, default: "inter", null: false
  end
end
