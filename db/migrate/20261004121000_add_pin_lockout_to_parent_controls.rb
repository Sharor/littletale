# frozen_string_literal: true

class AddPinLockoutToParentControls < ActiveRecord::Migration[8.0]
  def change
    add_column :parent_controls, :failed_pin_attempts, :integer, null: false, default: 0
    add_column :parent_controls, :locked_until, :datetime
  end
end
