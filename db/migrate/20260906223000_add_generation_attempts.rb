class AddGenerationAttempts < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :generation_attempt, :integer, null: false, default: 0
    add_column :books, :generation_failure_history, :jsonb, null: false, default: []
    add_column :pages, :generation_attempt, :integer, null: false, default: 0
    add_index :pages, [ :book_id, :generation_attempt ]
  end
end
