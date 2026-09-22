class AddArtStyleToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :art_style, :string, default: "western_book_style", null: false
  end
end
