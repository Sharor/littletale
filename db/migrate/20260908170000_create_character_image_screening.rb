class CreateCharacterImageScreening < ActiveRecord::Migration[8.0]
  def change
    create_table :character_image_assessments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.text :prompt, null: false
      t.string :model_name, null: false
      t.string :policy_version, null: false
      t.string :status, null: false, default: "checking"
      t.text :internal_reason
      t.text :public_reason
      t.jsonb :metadata, null: false, default: {}
      t.string :claim_token
      t.datetime :claimed_at
      t.integer :check_attempts, null: false, default: 0
      t.timestamps
    end
    add_index :character_image_assessments, [ :user_id, :fingerprint ], unique: true, name: "unique_owner_image_assessment"
    add_index :character_image_assessments, [ :status, :created_at ]

    create_table :character_image_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :character, foreign_key: { on_delete: :nullify }
      t.bigint :original_character_id, null: false
      t.references :assessment, null: false, foreign_key: { to_table: :character_image_assessments }
      t.boolean :provider_rejected, null: false, default: false
      t.text :rejection_reason
      t.timestamps
    end
    add_index :character_image_requests, [ :original_character_id, :assessment_id ], unique: true, name: "unique_character_image_request"
    add_reference :characters, :current_image_request, foreign_key: { to_table: :character_image_requests }

    create_table :character_image_decisions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :assessment, null: false, foreign_key: { to_table: :character_image_assessments }
      t.references :request, foreign_key: { to_table: :character_image_requests }
      t.references :reviewer, foreign_key: { to_table: :users }
      t.string :outcome, null: false
      t.string :source, null: false
      t.text :internal_reason
      t.text :public_reason
      t.timestamps
    end
    add_index :character_image_decisions, [ :user_id, :outcome, :created_at ], name: "image_decisions_reporting"

    create_table :character_image_generation_attempts do |t|
      t.references :request, null: false, index: { unique: true }, foreign_key: { to_table: :character_image_requests }
      t.references :action_log, null: false, index: { unique: true }, foreign_key: true
      t.string :status, null: false, default: "reserved"
      t.datetime :started_at
      t.datetime :finished_at
      t.string :provider_request_id
      t.jsonb :failure_metadata, null: false, default: {}
      t.references :illustration, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
  end
end
