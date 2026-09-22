class AddLanguagePreferences < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :language, :string
    add_column :users, :reader_age, :integer
    add_column :books, :language, :string
    add_column :books, :reader_age, :integer

    execute "UPDATE users SET language = 'en' WHERE language IS NULL"
    execute "UPDATE books SET language = 'en' WHERE language IS NULL"
  end

  def down
    remove_column :books, :reader_age
    remove_column :books, :language
    remove_column :users, :reader_age
    remove_column :users, :language
  end
end
