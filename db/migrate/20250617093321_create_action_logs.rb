class CreateActionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :action_logs do |t|
      t.references :trackable, polymorphic: true, null: false
      t.string :action

      t.timestamps
    end
  end
end
