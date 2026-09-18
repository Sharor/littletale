class AddCheckoutDetailsToBookPurchases < ActiveRecord::Migration[8.0]
  def change
    add_column :book_purchases, :checkout_url, :text
    add_column :book_purchases, :checkout_expires_at, :datetime
    add_index :book_purchases, :user_id, unique: true,
      where: "status = 'pending'", name: "index_one_pending_book_purchase_per_user"
  end
end
