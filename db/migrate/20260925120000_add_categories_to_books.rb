# frozen_string_literal: true

class AddCategoriesToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :categories, :json, default: [], null: false
  end
end
