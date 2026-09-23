# frozen_string_literal: true

class AddDeliverySecurityToBookGifts < ActiveRecord::Migration[8.0]
  def change
    add_column :book_gifts, :issuance_key, :string, null: false
    add_column :book_gifts, :invitation_token_ciphertext, :text, null: false
    add_column :book_gifts, :delivery_attempt_id, :string

    add_index :book_gifts, :issuance_key, unique: true
  end
end
