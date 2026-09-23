# frozen_string_literal: true

class AddGoogleEmailVerificationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :google_email_verified_at, :datetime
    add_index :users, :google_email_verified_at
  end
end
