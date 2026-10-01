# frozen_string_literal: true

class AddSubmissionAttemptTrackingToPrintOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :print_orders, :submission_attempted_at, :datetime
    add_column :print_orders, :submission_attempts, :json, null: false, default: []
  end
end
