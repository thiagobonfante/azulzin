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

ActiveRecord::Schema[8.1].define(version: 2026_07_06_000012) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bank_accounts", force: :cascade do |t|
    t.string "account_number"
    t.string "agency"
    t.datetime "balance_anchored_at"
    t.bigint "balance_cents"
    t.datetime "created_at", null: false
    t.bigint "institution_id", null: false
    t.string "kind", default: "checking", null: false
    t.string "nickname"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["institution_id"], name: "index_bank_accounts_on_institution_id"
    t.index ["user_id"], name: "index_bank_accounts_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "icon"
    t.citext "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_categories_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "commitments", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "archived_at"
    t.bigint "bank_account_id"
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.bigint "credit_card_id"
    t.date "ends_on"
    t.integer "installments_count"
    t.string "kind", null: false
    t.string "name", limit: 80, null: false
    t.integer "schedule_day"
    t.string "schedule_kind", default: "fixed_day", null: false
    t.string "source"
    t.string "source_message_id"
    t.date "starts_on", null: false
    t.bigint "total_cents"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["bank_account_id"], name: "index_commitments_on_bank_account_id"
    t.index ["category_id"], name: "index_commitments_on_category_id"
    t.index ["credit_card_id"], name: "index_commitments_on_credit_card_id"
    t.index ["source_message_id"], name: "index_commitments_on_source_message_id", unique: true, where: "(source_message_id IS NOT NULL)"
    t.index ["user_id", "kind"], name: "index_commitments_on_user_id_and_kind"
    t.index ["user_id"], name: "index_commitments_on_user_id"
    t.check_constraint "(kind::text = 'installment'::text) = (installments_count IS NOT NULL)", name: "commitments_installment_count_paired"
    t.check_constraint "num_nonnulls(bank_account_id, credit_card_id) = 1", name: "commitments_exactly_one_instrument"
  end

  create_table "credit_cards", force: :cascade do |t|
    t.integer "bill_due_day"
    t.string "card_type", default: "physical", null: false
    t.integer "closing_offset_days", default: 7, null: false
    t.datetime "created_at", null: false
    t.bigint "credit_limit_cents"
    t.bigint "current_bill_cents"
    t.bigint "institution_id", null: false
    t.string "last4"
    t.string "nickname"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["institution_id"], name: "index_credit_cards_on_institution_id"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
    t.check_constraint "bill_due_day >= 1 AND bill_due_day <= 31", name: "credit_cards_bill_due_day_range"
    t.check_constraint "closing_offset_days >= 0 AND closing_offset_days <= 28", name: "credit_cards_closing_offset_range"
  end

  create_table "document_imports", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.jsonb "extraction", default: {}, null: false
    t.jsonb "fingerprint", default: {}, null: false
    t.bigint "institution_id"
    t.string "kind"
    t.jsonb "proposals", default: [], null: false
    t.string "source_format"
    t.string "status", default: "uploaded", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["institution_id"], name: "index_document_imports_on_institution_id"
    t.index ["user_id", "checksum"], name: "index_document_imports_dedupe_checksum", unique: true, where: "((status)::text <> ALL (ARRAY[('dismissed'::character varying)::text, ('failed'::character varying)::text]))"
    t.index ["user_id", "status"], name: "index_document_imports_on_user_id_and_status"
    t.index ["user_id"], name: "index_document_imports_on_user_id"
  end

  create_table "incomes", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "archived_at"
    t.bigint "bank_account_id", null: false
    t.datetime "created_at", null: false
    t.string "name", limit: 80, null: false
    t.integer "schedule_day", null: false
    t.string "schedule_kind", default: "fixed_day", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["bank_account_id"], name: "index_incomes_on_bank_account_id"
    t.index ["user_id"], name: "index_incomes_on_user_id"
  end

  create_table "institutions", force: :cascade do |t|
    t.string "brand_color", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "initials", null: false
    t.string "logo_path"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "supports_account", default: true, null: false
    t.boolean "supports_card", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_institutions_on_code", unique: true
    t.index ["position"], name: "index_institutions_on_position"
  end

  create_table "oauth_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_oauth_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_oauth_identities_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.jsonb "ask", default: {}, null: false
    t.datetime "ask_expires_at"
    t.bigint "bank_account_id"
    t.date "billing_month", null: false
    t.boolean "billing_month_manual", default: false, null: false
    t.bigint "category_id"
    t.bigint "commitment_id"
    t.integer "confidence"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "credit_card_id"
    t.string "description"
    t.string "direction", default: "expense", null: false
    t.jsonb "extraction", default: {}, null: false
    t.bigint "income_id"
    t.integer "installment_number"
    t.jsonb "match_meta", default: {}, null: false
    t.string "merchant"
    t.date "occurred_on", null: false
    t.string "payment_method"
    t.string "source"
    t.string "source_message_id"
    t.string "status", default: "pending_review", null: false
    t.bigint "transfer_to_bank_account_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "whatsapp_message_id"
    t.index ["bank_account_id"], name: "index_transactions_on_bank_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["commitment_id", "billing_month"], name: "index_transactions_commitment_paid_once", unique: true, where: "((commitment_id IS NOT NULL) AND ((status)::text = 'posted'::text) AND ((installment_number IS NULL) OR (credit_card_id IS NULL)))"
    t.index ["commitment_id"], name: "index_transactions_on_commitment_id"
    t.index ["credit_card_id", "billing_month"], name: "index_transactions_on_card_and_billing_month", where: "(credit_card_id IS NOT NULL)"
    t.index ["credit_card_id"], name: "index_transactions_on_credit_card_id"
    t.index ["income_id"], name: "index_transactions_on_income_id"
    t.index ["source_message_id"], name: "index_transactions_on_source_message_id", unique: true, where: "(source_message_id IS NOT NULL)"
    t.index ["transfer_to_bank_account_id"], name: "index_transactions_on_transfer_to_bank_account_id"
    t.index ["user_id", "billing_month"], name: "index_transactions_on_user_id_and_billing_month"
    t.index ["user_id", "status"], name: "index_transactions_on_user_id_and_status"
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.index ["whatsapp_message_id"], name: "index_transactions_on_whatsapp_message_id"
    t.check_constraint "installment_number IS NULL OR commitment_id IS NOT NULL", name: "transactions_installment_requires_commitment"
    t.check_constraint "num_nonnulls(bank_account_id, credit_card_id) <= 1", name: "transactions_one_instrument_max"
    t.check_constraint "transfer_to_bank_account_id IS NULL OR direction::text = 'transfer'::text", name: "transactions_transfer_dest_only_on_transfer"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.citext "email_address", null: false
    t.string "locale", default: "pt-BR", null: false
    t.string "name"
    t.datetime "onboarded_at"
    t.string "password_digest"
    t.string "phone"
    t.datetime "phone_verified_at"
    t.datetime "updated_at", null: false
    t.string "whatsapp_id"
    t.string "whatsapp_jid"
    t.string "whatsapp_verification_code"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["whatsapp_id"], name: "index_users_on_whatsapp_id", unique: true, where: "(whatsapp_id IS NOT NULL)"
    t.index ["whatsapp_verification_code"], name: "index_users_on_whatsapp_verification_code", unique: true, where: "(whatsapp_verification_code IS NOT NULL)"
  end

  create_table "whatsapp_connections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_connected_at"
    t.text "last_error"
    t.datetime "last_seen_at"
    t.text "qr_data_url"
    t.string "status", default: "disconnected", null: false
    t.datetime "updated_at", null: false
    t.string "wa_id"
  end

  create_table "whatsapp_messages", force: :cascade do |t|
    t.jsonb "ai_result", default: {}, null: false
    t.text "body"
    t.string "chat_id"
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.text "error"
    t.string "message_type"
    t.datetime "processed_at"
    t.string "status", default: "received", null: false
    t.bigint "transaction_id"
    t.text "transcription"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "wa_message_id"
    t.index ["transaction_id"], name: "index_whatsapp_messages_on_transaction_id"
    t.index ["user_id", "created_at"], name: "index_whatsapp_messages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_whatsapp_messages_on_user_id"
    t.index ["wa_message_id"], name: "index_whatsapp_messages_on_wa_message_id", unique: true, where: "(wa_message_id IS NOT NULL)"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bank_accounts", "institutions"
  add_foreign_key "bank_accounts", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "commitments", "bank_accounts"
  add_foreign_key "commitments", "categories"
  add_foreign_key "commitments", "credit_cards"
  add_foreign_key "commitments", "users"
  add_foreign_key "credit_cards", "institutions"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "document_imports", "institutions"
  add_foreign_key "document_imports", "users"
  add_foreign_key "incomes", "bank_accounts"
  add_foreign_key "incomes", "users"
  add_foreign_key "oauth_identities", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "bank_accounts"
  add_foreign_key "transactions", "bank_accounts", column: "transfer_to_bank_account_id"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "commitments"
  add_foreign_key "transactions", "credit_cards"
  add_foreign_key "transactions", "incomes"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "whatsapp_messages"
  add_foreign_key "whatsapp_messages", "transactions"
  add_foreign_key "whatsapp_messages", "users"
end
