# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_09_25_121000) do
  create_table "action_logs", force: :cascade do |t|
    t.string "trackable_type", null: false
    t.integer "trackable_id", null: false
    t.string "action"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trackable_type", "trackable_id"], name: "index_action_logs_on_trackable"
    t.index ["user_id"], name: "index_action_logs_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "book_credit_reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_credit_id", null: false
    t.integer "book_id"
    t.string "status", default: "held", null: false
    t.datetime "released_at"
    t.integer "released_by_id"
    t.string "release_reason"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_credit_id"], name: "index_book_credit_reservations_on_book_credit_id"
    t.index ["book_credit_id"], name: "index_held_reservation_per_book_credit", unique: true, where: "status = 'held'"
    t.index ["book_id"], name: "index_held_book_credit_reservation_per_book", unique: true, where: "status = 'held'"
    t.index ["released_by_id"], name: "index_book_credit_reservations_on_released_by_id"
    t.index ["user_id", "status"], name: "index_book_credit_reservations_on_user_id_and_status"
    t.index ["user_id"], name: "index_book_credit_reservations_on_user_id"
  end

  create_table "book_credits", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_purchase_id"
    t.string "status", default: "available", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "subscription_period_id"
    t.boolean "visible", default: true, null: false
    t.datetime "expires_at"
    t.index ["book_purchase_id"], name: "index_book_credits_on_book_purchase_id", unique: true
    t.index ["subscription_period_id", "id"], name: "index_book_credits_on_subscription_period_and_id"
    t.index ["subscription_period_id"], name: "index_book_credits_on_subscription_period_id"
    t.index ["user_id", "status"], name: "index_book_credits_on_user_id_and_status"
    t.index ["user_id", "visible", "status"], name: "index_book_credits_on_user_visibility_status"
    t.index ["user_id"], name: "index_book_credits_on_user_id"
  end

  create_table "book_gifts", force: :cascade do |t|
    t.integer "source_book_id"
    t.integer "sender_id"
    t.integer "recipient_id"
    t.string "recipient_name", null: false
    t.string "recipient_email", null: false
    t.string "sender_callname", null: false
    t.text "message", null: false
    t.string "language", null: false
    t.string "title", null: false
    t.string "token_digest", null: false
    t.datetime "claimed_at"
    t.string "delivery_status", default: "not_sent", null: false
    t.text "delivery_error"
    t.datetime "email_queued_at"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "issuance_key", null: false
    t.text "invitation_token_ciphertext", null: false
    t.string "delivery_attempt_id"
    t.index ["issuance_key"], name: "index_book_gifts_on_issuance_key", unique: true
    t.index ["recipient_id", "claimed_at"], name: "index_book_gifts_on_recipient_id_and_claimed_at"
    t.index ["recipient_id"], name: "index_book_gifts_on_recipient_id"
    t.index ["sender_id"], name: "index_book_gifts_on_sender_id"
    t.index ["source_book_id"], name: "index_book_gifts_on_source_book_id"
    t.index ["token_digest"], name: "index_book_gifts_on_token_digest", unique: true
  end

  create_table "book_outfits", force: :cascade do |t|
    t.integer "book_wardrobe_plan_id", null: false
    t.bigint "character_id", null: false
    t.string "outfit_key", null: false
    t.text "description", null: false
    t.json "page_numbers", default: [], null: false
    t.json "character_snapshot", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.json "generation_metadata", default: {}, null: false
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_wardrobe_plan_id", "character_id", "outfit_key"], name: "index_book_outfits_unique_identity", unique: true
    t.index ["book_wardrobe_plan_id"], name: "index_book_outfits_on_book_wardrobe_plan_id"
  end

  create_table "book_purchases", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "product_id", null: false
    t.string "price_id"
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.string "stripe_customer_id"
    t.string "idempotency_key", null: false
    t.integer "amount_total"
    t.string "currency"
    t.boolean "livemode", default: false, null: false
    t.datetime "paid_at"
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "checkout_url"
    t.datetime "checkout_expires_at"
    t.index ["idempotency_key"], name: "index_book_purchases_on_idempotency_key", unique: true
    t.index ["stripe_checkout_session_id"], name: "index_book_purchases_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_book_purchases_on_stripe_payment_intent_id", unique: true
    t.index ["user_id"], name: "index_book_purchases_on_user_id"
    t.index ["user_id"], name: "index_one_pending_book_purchase_per_user", unique: true, where: "status = 'pending'"
  end

  create_table "book_wardrobe_plans", force: :cascade do |t|
    t.integer "book_id", null: false
    t.integer "generation_attempt", null: false
    t.string "status", default: "pending", null: false
    t.json "story", default: [], null: false
    t.json "character_snapshots", default: [], null: false
    t.json "failure", default: {}, null: false
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "generation_attempt"], name: "index_book_wardrobe_plans_on_book_id_and_generation_attempt", unique: true
    t.index ["book_id"], name: "index_book_wardrobe_plans_on_book_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "name"
    t.string "plot"
    t.integer "page_count"
    t.string "text_context"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "generation_status", default: 0
    t.integer "total_pages"
    t.json "generation_failure", default: {}, null: false
    t.datetime "generation_failed_at"
    t.integer "generation_attempt", default: 0, null: false
    t.json "generation_failure_history", default: [], null: false
    t.string "language"
    t.integer "reader_age"
    t.string "art_style", default: "western_book_style", null: false
    t.json "categories", default: [], null: false
    t.datetime "categorization_enqueued_at"
    t.index ["user_id"], name: "index_books_on_user_id"
  end

  create_table "books_characters", id: false, force: :cascade do |t|
    t.integer "book_id", null: false
    t.integer "character_id", null: false
    t.index ["book_id", "character_id"], name: "index_books_characters_on_book_id_and_character_id"
    t.index ["character_id", "book_id"], name: "index_books_characters_on_character_id_and_book_id"
  end

  create_table "character_credit_reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "character_credit_id", null: false
    t.integer "character_image_request_id"
    t.string "status", default: "held", null: false
    t.datetime "released_at"
    t.integer "released_by_id"
    t.string "release_reason"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_credit_id"], name: "index_character_credit_reservations_on_character_credit_id"
    t.index ["character_credit_id"], name: "index_held_reservation_per_character_credit", unique: true, where: "status = 'held'"
    t.index ["character_image_request_id"], name: "index_held_character_credit_reservation_per_request", unique: true, where: "status = 'held'"
    t.index ["released_by_id"], name: "index_character_credit_reservations_on_released_by_id"
    t.index ["user_id", "status"], name: "index_character_credit_reservations_on_user_id_and_status"
    t.index ["user_id"], name: "index_character_credit_reservations_on_user_id"
  end

  create_table "character_credits", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_purchase_id"
    t.integer "ordinal", null: false
    t.string "status", default: "available", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "subscription_period_id"
    t.boolean "visible", default: true, null: false
    t.datetime "expires_at"
    t.index ["book_purchase_id", "ordinal"], name: "index_character_credits_on_book_purchase_id_and_ordinal", unique: true
    t.index ["book_purchase_id"], name: "index_character_credits_on_book_purchase_id"
    t.index ["subscription_period_id", "ordinal"], name: "index_character_credits_on_period_and_ordinal", unique: true, where: "subscription_period_id IS NOT NULL"
    t.index ["subscription_period_id"], name: "index_character_credits_on_subscription_period_id"
    t.index ["user_id", "status"], name: "index_character_credits_on_user_id_and_status"
    t.index ["user_id", "visible", "status"], name: "index_character_credits_on_user_visibility_status"
    t.index ["user_id"], name: "index_character_credits_on_user_id"
  end

  create_table "character_image_assessments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "fingerprint", null: false
    t.text "prompt", null: false
    t.string "generation_model", null: false
    t.string "policy_version", null: false
    t.string "status", default: "checking", null: false
    t.text "internal_reason"
    t.text "public_reason"
    t.json "metadata", default: {}, null: false
    t.string "claim_token"
    t.datetime "claimed_at"
    t.integer "check_attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "created_at"], name: "index_character_image_assessments_on_status_and_created_at"
    t.index ["user_id", "fingerprint"], name: "unique_owner_image_assessment", unique: true
    t.index ["user_id"], name: "index_character_image_assessments_on_user_id"
  end

  create_table "character_image_decisions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "assessment_id", null: false
    t.integer "request_id"
    t.integer "reviewer_id"
    t.string "outcome", null: false
    t.string "source", null: false
    t.text "internal_reason"
    t.text "public_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_id"], name: "index_character_image_decisions_on_assessment_id"
    t.index ["request_id"], name: "index_character_image_decisions_on_request_id"
    t.index ["reviewer_id"], name: "index_character_image_decisions_on_reviewer_id"
    t.index ["user_id", "outcome", "created_at"], name: "image_decisions_reporting"
    t.index ["user_id"], name: "index_character_image_decisions_on_user_id"
  end

  create_table "character_image_generation_attempts", force: :cascade do |t|
    t.integer "request_id", null: false
    t.integer "action_log_id", null: false
    t.string "status", default: "reserved", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string "provider_request_id"
    t.json "failure_metadata", default: {}, null: false
    t.integer "illustration_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_log_id"], name: "index_character_image_generation_attempts_on_action_log_id", unique: true
    t.index ["illustration_id"], name: "index_character_image_generation_attempts_on_illustration_id"
    t.index ["request_id"], name: "index_character_image_generation_attempts_on_request_id", unique: true
  end

  create_table "character_image_requests", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "character_id"
    t.bigint "original_character_id", null: false
    t.integer "assessment_id", null: false
    t.boolean "provider_rejected", default: false, null: false
    t.text "rejection_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "funding_source"
    t.index ["assessment_id"], name: "index_character_image_requests_on_assessment_id"
    t.index ["character_id"], name: "index_character_image_requests_on_character_id"
    t.index ["funding_source"], name: "index_character_image_requests_on_funding_source"
    t.index ["original_character_id", "assessment_id"], name: "unique_character_image_request", unique: true
    t.index ["user_id"], name: "index_character_image_requests_on_user_id"
  end

  create_table "characters", force: :cascade do |t|
    t.string "name"
    t.integer "age"
    t.string "gender"
    t.string "hair_color"
    t.string "hair_style"
    t.string "eye_color"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ethnicity"
    t.json "roles", default: [], null: false
    t.integer "generation_status", default: 0
    t.integer "current_image_request_id"
    t.index ["current_image_request_id"], name: "index_characters_on_current_image_request_id"
    t.index ["user_id"], name: "index_characters_on_user_id"
  end

  create_table "chatgpts", force: :cascade do |t|
    t.text "prompt"
    t.text "answer"
    t.integer "max_tokens"
    t.integer "audience"
    t.text "reason_for_termination"
    t.text "usage"
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_chatgpts_on_book_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "path", null: false
    t.string "method", null: false
    t.string "params"
    t.integer "visitor_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["visitor_id"], name: "index_events_on_visitor_id"
  end

  create_table "gift_pages", force: :cascade do |t|
    t.integer "book_gift_id", null: false
    t.integer "position", null: false
    t.text "text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_gift_id", "position"], name: "index_gift_pages_on_book_gift_id_and_position", unique: true
    t.index ["book_gift_id"], name: "index_gift_pages_on_book_gift_id"
  end

  create_table "illustrations", force: :cascade do |t|
    t.string "prompt"
    t.string "image_url"
    t.string "original_image"
    t.string "original_description"
    t.integer "page_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "character_id"
    t.json "generation_metadata", default: {}, null: false
    t.index ["character_id"], name: "index_illustrations_on_character_id"
    t.index ["page_id"], name: "index_illustrations_on_page_id"
  end

  create_table "pages", force: :cascade do |t|
    t.string "image_description"
    t.string "text"
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "generation_attempt", default: 0, null: false
    t.integer "book_wardrobe_plan_id"
    t.integer "story_position"
    t.index ["book_id", "generation_attempt", "story_position"], name: "index_pages_unique_story_position", unique: true
    t.index ["book_id", "generation_attempt"], name: "index_pages_on_book_id_and_generation_attempt"
    t.index ["book_id"], name: "index_pages_on_book_id"
    t.index ["book_wardrobe_plan_id"], name: "index_pages_on_book_wardrobe_plan_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.string "stripe_object_id"
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type", "stripe_object_id"], name: "index_stripe_events_on_type_and_object"
    t.index ["stripe_event_id"], name: "index_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "subscription_periods", force: :cascade do |t|
    t.integer "user_subscription_id", null: false
    t.string "stripe_invoice_id", null: false
    t.string "price_id", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_invoice_id"], name: "index_subscription_periods_on_stripe_invoice_id", unique: true
    t.index ["user_subscription_id", "period_start"], name: "idx_on_user_subscription_id_period_start_7775b0bb53", unique: true
    t.index ["user_subscription_id"], name: "index_subscription_periods_on_user_subscription_id"
  end

  create_table "trial_book_reservations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_id"
    t.string "status", default: "held", null: false
    t.datetime "released_at"
    t.integer "released_by_id"
    t.string "release_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_held_trial_reservation_per_book", unique: true, where: "status = 'held'"
    t.index ["released_by_id"], name: "index_trial_book_reservations_on_released_by_id"
    t.index ["user_id", "status"], name: "index_trial_book_reservations_on_user_id_and_status"
    t.index ["user_id"], name: "index_trial_book_reservations_on_user_id"
  end

  create_table "tutorials", force: :cascade do |t|
    t.boolean "eula"
    t.boolean "terms"
    t.boolean "tutorial_complete"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_tutorials_on_user_id"
  end

  create_table "user_subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "product_id", null: false
    t.string "price_id"
    t.string "stripe_subscription_id"
    t.string "stripe_checkout_session_id"
    t.string "stripe_customer_id"
    t.string "idempotency_key", null: false
    t.boolean "livemode", default: false, null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "ended_at"
    t.text "checkout_url"
    t.datetime "checkout_expires_at"
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_user_subscriptions_on_idempotency_key", unique: true
    t.index ["stripe_checkout_session_id"], name: "index_user_subscriptions_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_subscription_id"], name: "index_user_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_one_current_user_subscription", unique: true, where: "status IN ('pending', 'active', 'past_due', 'unpaid')"
    t.index ["user_id"], name: "index_user_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "tier"
    t.datetime "trial_started_at"
    t.datetime "trial_expires_at"
    t.string "stripe_customer_id"
    t.string "language"
    t.integer "reader_age"
    t.datetime "google_email_verified_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_email_verified_at"], name: "index_users_on_google_email_verified_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true
  end

  create_table "visitors", force: :cascade do |t|
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_visitors_on_user_id"
  end

  add_foreign_key "action_logs", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "book_credit_reservations", "book_credits"
  add_foreign_key "book_credit_reservations", "books", on_delete: :nullify
  add_foreign_key "book_credit_reservations", "users"
  add_foreign_key "book_credit_reservations", "users", column: "released_by_id", on_delete: :nullify
  add_foreign_key "book_credits", "book_purchases"
  add_foreign_key "book_credits", "subscription_periods"
  add_foreign_key "book_credits", "users"
  add_foreign_key "book_gifts", "books", column: "source_book_id", on_delete: :nullify
  add_foreign_key "book_gifts", "users", column: "recipient_id", on_delete: :nullify
  add_foreign_key "book_gifts", "users", column: "sender_id", on_delete: :nullify
  add_foreign_key "book_outfits", "book_wardrobe_plans"
  add_foreign_key "book_purchases", "users"
  add_foreign_key "book_wardrobe_plans", "books"
  add_foreign_key "books", "users", on_delete: :cascade
  add_foreign_key "character_credit_reservations", "character_credits"
  add_foreign_key "character_credit_reservations", "character_image_requests", on_delete: :nullify
  add_foreign_key "character_credit_reservations", "users"
  add_foreign_key "character_credit_reservations", "users", column: "released_by_id", on_delete: :nullify
  add_foreign_key "character_credits", "book_purchases"
  add_foreign_key "character_credits", "subscription_periods"
  add_foreign_key "character_credits", "users"
  add_foreign_key "character_image_assessments", "users"
  add_foreign_key "character_image_decisions", "character_image_assessments", column: "assessment_id"
  add_foreign_key "character_image_decisions", "character_image_requests", column: "request_id"
  add_foreign_key "character_image_decisions", "users"
  add_foreign_key "character_image_decisions", "users", column: "reviewer_id"
  add_foreign_key "character_image_generation_attempts", "action_logs"
  add_foreign_key "character_image_generation_attempts", "character_image_requests", column: "request_id"
  add_foreign_key "character_image_generation_attempts", "illustrations", on_delete: :nullify
  add_foreign_key "character_image_requests", "character_image_assessments", column: "assessment_id"
  add_foreign_key "character_image_requests", "characters", on_delete: :nullify
  add_foreign_key "character_image_requests", "users"
  add_foreign_key "characters", "character_image_requests", column: "current_image_request_id"
  add_foreign_key "characters", "users", on_delete: :cascade
  add_foreign_key "chatgpts", "books", on_delete: :cascade
  add_foreign_key "events", "visitors", on_delete: :cascade
  add_foreign_key "gift_pages", "book_gifts", on_delete: :cascade
  add_foreign_key "illustrations", "characters", on_delete: :cascade
  add_foreign_key "illustrations", "pages", on_delete: :cascade
  add_foreign_key "pages", "book_wardrobe_plans"
  add_foreign_key "pages", "books", on_delete: :cascade
  add_foreign_key "subscription_periods", "user_subscriptions"
  add_foreign_key "trial_book_reservations", "books", on_delete: :nullify
  add_foreign_key "trial_book_reservations", "users"
  add_foreign_key "trial_book_reservations", "users", column: "released_by_id", on_delete: :nullify
  add_foreign_key "tutorials", "users", on_delete: :cascade
  add_foreign_key "user_subscriptions", "users"
  add_foreign_key "visitors", "users", on_delete: :cascade
end
