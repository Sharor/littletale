class AddUserToActionLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :action_logs, :user, null: false, foreign_key: true
  end
end
