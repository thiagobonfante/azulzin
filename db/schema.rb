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

ActiveRecord::Schema[8.1].define(version: 2026_07_23_122202) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["account_id"], name: "index_account_memberships_one_owner", unique: true, where: "((role)::text = 'owner'::text)"
    t.index ["user_id"], name: "index_account_memberships_on_user_id", unique: true
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "category_backfill_at"
    t.datetime "created_at", null: false
    t.integer "members_count", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "members_count >= 0 AND members_count <= 4", name: "accounts_members_count_cap"
  end

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
    t.bigint "account_id", null: false
    t.string "account_number"
    t.string "agency"
    t.datetime "balance_anchored_at"
    t.bigint "balance_cents"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.bigint "institution_id", null: false
    t.string "kind", default: "checking", null: false
    t.string "nickname"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id"], name: "index_bank_accounts_on_account_id"
    t.index ["created_by_id"], name: "index_bank_accounts_on_created_by_id"
    t.index ["institution_id"], name: "index_bank_accounts_on_institution_id"
  end

  create_table "bcb_rates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.string "kind", null: false
    t.decimal "monthly_rate", precision: 8, scale: 4, null: false
    t.date "reference_month", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "reference_month"], name: "index_bcb_rates_on_kind_and_reference_month", unique: true
  end

  create_table "card_bill_financings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "card_bill_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "down_payment_transaction_id"
    t.bigint "financed_cents", null: false
    t.date "first_charge_month", null: false
    t.bigint "installment_cents", null: false
    t.integer "installments_count", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id"], name: "index_card_bill_financings_on_account_id"
    t.index ["card_bill_id"], name: "index_card_bill_financings_on_card_bill_id", unique: true
    t.index ["created_by_id"], name: "index_card_bill_financings_on_created_by_id"
    t.index ["down_payment_transaction_id"], name: "index_card_bill_financings_on_down_payment_transaction_id"
    t.index ["updated_by_id"], name: "index_card_bill_financings_on_updated_by_id"
  end

  create_table "card_bills", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "billing_month", null: false
    t.date "closed_on", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_card_id", null: false
    t.date "due_on", null: false
    t.jsonb "review_log", default: [], null: false
    t.bigint "stated_minimum_cents"
    t.bigint "stated_total_cents"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id"], name: "index_card_bills_on_account_id"
    t.index ["created_by_id"], name: "index_card_bills_on_created_by_id"
    t.index ["credit_card_id", "billing_month"], name: "index_card_bills_on_credit_card_id_and_billing_month", unique: true
    t.index ["updated_by_id"], name: "index_card_bills_on_updated_by_id"
  end

  create_table "categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.string "flexibility"
    t.string "icon"
    t.bigint "monthly_budget_cents"
    t.citext "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id", "name"], name: "index_categories_on_account_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["account_id"], name: "index_categories_on_account_id"
    t.index ["created_by_id"], name: "index_categories_on_created_by_id"
  end

  create_table "commitments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "amount_cents", null: false
    t.datetime "archived_at"
    t.bigint "bank_account_id"
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_card_id"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.date "ends_on"
    t.bigint "goal_id"
    t.integer "installments_count"
    t.string "kind", null: false
    t.string "name", limit: 80, null: false
    t.integer "schedule_day"
    t.string "schedule_kind", default: "fixed_day", null: false
    t.string "source"
    t.string "source_message_id"
    t.date "starts_on", null: false
    t.bigint "total_cents"
    t.bigint "transfer_to_bank_account_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id", "kind"], name: "index_commitments_on_account_id_and_kind"
    t.index ["account_id"], name: "index_commitments_on_account_id"
    t.index ["bank_account_id"], name: "index_commitments_on_bank_account_id"
    t.index ["category_id"], name: "index_commitments_on_category_id"
    t.index ["created_by_id"], name: "index_commitments_on_created_by_id"
    t.index ["credit_card_id"], name: "index_commitments_on_credit_card_id"
    t.index ["goal_id"], name: "index_commitments_on_goal_id"
    t.index ["goal_id"], name: "index_commitments_one_active_per_goal", unique: true, where: "((goal_id IS NOT NULL) AND (archived_at IS NULL) AND (deleted_at IS NULL))"
    t.index ["source_message_id"], name: "index_commitments_on_source_message_id", unique: true, where: "(source_message_id IS NOT NULL)"
    t.index ["transfer_to_bank_account_id"], name: "index_commitments_on_transfer_to_bank_account_id"
    t.check_constraint "(kind::text = 'installment'::text) = (installments_count IS NOT NULL)", name: "commitments_installment_count_paired"
    t.check_constraint "num_nonnulls(bank_account_id, credit_card_id) = 1", name: "commitments_exactly_one_instrument"
  end

  create_table "credit_cards", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "bill_due_day"
    t.string "card_type", default: "physical", null: false
    t.integer "closing_offset_days", default: 7, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_limit_cents"
    t.bigint "current_bill_cents"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.bigint "institution_id", null: false
    t.string "last4"
    t.string "nickname"
    t.bigint "parent_card_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id"], name: "index_credit_cards_on_account_id"
    t.index ["created_by_id"], name: "index_credit_cards_on_created_by_id"
    t.index ["institution_id"], name: "index_credit_cards_on_institution_id"
    t.index ["parent_card_id"], name: "index_credit_cards_on_parent_card_id"
    t.check_constraint "bill_due_day >= 1 AND bill_due_day <= 31", name: "credit_cards_bill_due_day_range"
    t.check_constraint "closing_offset_days >= 0 AND closing_offset_days <= 28", name: "credit_cards_closing_offset_range"
  end

  create_table "document_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "bank_account_id"
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_card_id"
    t.string "error_code"
    t.jsonb "extraction", default: {}, null: false
    t.jsonb "fingerprint", default: {}, null: false
    t.bigint "institution_id"
    t.string "kind"
    t.date "period"
    t.jsonb "proposals", default: [], null: false
    t.string "purpose", default: "onboarding", null: false
    t.string "source_format"
    t.string "status", default: "uploaded", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id", "checksum"], name: "index_document_imports_dedupe_checksum", unique: true, where: "((status)::text <> ALL (ARRAY[('dismissed'::character varying)::text, ('failed'::character varying)::text]))"
    t.index ["account_id", "status"], name: "index_document_imports_on_account_id_and_status"
    t.index ["account_id"], name: "index_document_imports_on_account_id"
    t.index ["bank_account_id"], name: "index_document_imports_on_bank_account_id"
    t.index ["created_by_id"], name: "index_document_imports_on_created_by_id"
    t.index ["credit_card_id"], name: "index_document_imports_on_credit_card_id"
    t.index ["institution_id"], name: "index_document_imports_on_institution_id"
    t.check_constraint "purpose::text <> 'reconciliation'::text OR num_nonnulls(credit_card_id, bank_account_id) = 1", name: "document_imports_reconciliation_target"
  end

  create_table "goal_checks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "actual_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "expected_cents", default: 0, null: false
    t.jsonb "findings", default: [], null: false
    t.bigint "goal_id", null: false
    t.date "period_start", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_goal_checks_on_account_id"
    t.index ["goal_id", "period_start"], name: "index_goal_checks_on_goal_id_and_period_start", unique: true
  end

  create_table "goal_conversations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "expires_at", null: false
    t.bigint "goal_id"
    t.string "status", default: "collecting", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_goal_conversations_on_account_id"
    t.index ["goal_id"], name: "index_goal_conversations_on_goal_id"
    t.index ["user_id"], name: "index_goal_conversations_on_user_id"
    t.index ["user_id"], name: "index_goal_conversations_one_open_per_user", unique: true, where: "((status)::text <> 'closed'::text)"
  end

  create_table "goals", force: :cascade do |t|
    t.datetime "abandoned_at"
    t.bigint "account_id", null: false
    t.datetime "achieved_at"
    t.datetime "activated_at"
    t.integer "ai_calls_count", default: 0, null: false
    t.bigint "bank_account_id"
    t.jsonb "baseline", default: {}, null: false
    t.datetime "budgets_applied_at"
    t.datetime "celebrated_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "initial_saved_bank_account_id"
    t.bigint "initial_saved_cents", default: 0, null: false
    t.string "kind", null: false
    t.bigint "monthly_target_cents"
    t.string "name", limit: 80, null: false
    t.jsonb "plan", default: {}, null: false
    t.jsonb "previous_budgets", default: {}, null: false
    t.date "starts_on"
    t.string "status", default: "draft", null: false
    t.bigint "target_cents", null: false
    t.date "target_date"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.jsonb "user_caps", default: {}, null: false
    t.index ["account_id", "status"], name: "index_goals_on_account_id_and_status"
    t.index ["account_id"], name: "index_goals_on_account_id"
    t.index ["bank_account_id"], name: "index_goals_on_bank_account_id"
    t.index ["created_by_id"], name: "index_goals_on_created_by_id"
    t.index ["initial_saved_bank_account_id"], name: "index_goals_on_initial_saved_bank_account_id"
    t.check_constraint "(kind::text = 'purchase'::text) = (target_date IS NOT NULL)", name: "goals_purchase_has_date"
    t.check_constraint "initial_saved_cents >= 0", name: "goals_initial_saved_non_negative"
    t.check_constraint "monthly_target_cents IS NULL OR monthly_target_cents > 0", name: "goals_monthly_target_positive"
    t.check_constraint "target_cents > 0", name: "goals_target_positive"
  end

  create_table "incomes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "amount_cents", null: false
    t.datetime "archived_at"
    t.bigint "bank_account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.string "name", limit: 80, null: false
    t.integer "schedule_day", null: false
    t.string "schedule_kind", default: "fixed_day", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["account_id"], name: "index_incomes_on_account_id"
    t.index ["bank_account_id"], name: "index_incomes_on_bank_account_id"
    t.index ["created_by_id"], name: "index_incomes_on_created_by_id"
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

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.datetime "expires_at", null: false
    t.bigint "invited_by_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "email"], name: "index_invitations_open_per_email", unique: true, where: "(accepted_at IS NULL)"
    t.index ["account_id"], name: "index_invitations_on_account_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.integer "bill_reminder_lead_days", default: 1, null: false
    t.boolean "bill_reminders", default: true, null: false
    t.boolean "budget_alerts", default: true, null: false
    t.integer "budget_breach_percent", default: 100, null: false
    t.integer "budget_warn_percent", default: 80, null: false
    t.datetime "created_at", null: false
    t.boolean "goal_achieved", default: true, null: false
    t.boolean "goal_alerts", default: false, null: false
    t.boolean "monthly_summary", default: false, null: false
    t.boolean "push_enabled", default: true, null: false
    t.integer "quiet_hours_end", default: 8, null: false
    t.integer "quiet_hours_start", default: 21, null: false
    t.boolean "surplus_nudges", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "wa_intro_sent_at"
    t.boolean "weekly_summary", default: false, null: false
    t.boolean "whatsapp_consent", default: false, null: false
    t.index ["user_id"], name: "index_notification_preferences_on_user_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.date "period_key", null: false
    t.datetime "push_sent_at"
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.datetime "whatsapp_sent_at"
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["user_id", "dismissed_at"], name: "index_notifications_on_user_id_and_dismissed_at"
    t.index ["user_id", "kind", "subject_type", "subject_id", "period_key"], name: "index_notifications_dedup", unique: true, nulls_not_distinct: true
    t.index ["user_id"], name: "index_notifications_on_user_id"
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

  create_table "push_devices", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.datetime "last_registered_at", null: false
    t.string "platform", null: false
    t.bigint "session_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["session_id"], name: "index_push_devices_on_session_id"
    t.index ["token"], name: "index_push_devices_on_token", unique: true
    t.index ["user_id"], name: "index_push_devices_on_user_id"
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
    t.bigint "account_id", null: false
    t.bigint "amount_cents", null: false
    t.jsonb "ask", default: {}, null: false
    t.datetime "ask_expires_at"
    t.bigint "bank_account_id"
    t.date "billing_month", null: false
    t.boolean "billing_month_manual", default: false, null: false
    t.bigint "card_bill_id"
    t.bigint "category_id"
    t.string "category_source"
    t.bigint "commitment_id"
    t.integer "confidence"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_card_id"
    t.datetime "deleted_at"
    t.bigint "deleted_by_id"
    t.string "description"
    t.string "direction", default: "expense", null: false
    t.jsonb "extraction", default: {}, null: false
    t.bigint "income_id"
    t.integer "installment_number"
    t.jsonb "match_meta", default: {}, null: false
    t.string "merchant"
    t.string "merchant_norm"
    t.date "occurred_on", null: false
    t.string "payment_method"
    t.string "source"
    t.string "source_message_id"
    t.string "status", default: "pending_review", null: false
    t.bigint "transfer_to_bank_account_id"
    t.bigint "transfer_to_credit_card_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.bigint "whatsapp_message_id"
    t.index ["account_id", "billing_month"], name: "index_transactions_on_account_id_and_billing_month"
    t.index ["account_id", "merchant_norm"], name: "index_transactions_on_account_id_and_merchant_norm"
    t.index ["account_id", "status"], name: "index_transactions_on_account_id_and_status"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["bank_account_id"], name: "index_transactions_on_bank_account_id"
    t.index ["card_bill_id"], name: "index_transactions_on_card_bill_id", where: "(card_bill_id IS NOT NULL)"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["commitment_id", "billing_month"], name: "index_transactions_commitment_paid_once", unique: true, where: "((commitment_id IS NOT NULL) AND ((status)::text = 'posted'::text) AND ((installment_number IS NULL) OR (credit_card_id IS NULL)) AND (deleted_at IS NULL))"
    t.index ["commitment_id"], name: "index_transactions_on_commitment_id"
    t.index ["created_by_id"], name: "index_transactions_on_created_by_id"
    t.index ["credit_card_id", "billing_month"], name: "index_transactions_on_card_and_billing_month", where: "(credit_card_id IS NOT NULL)"
    t.index ["credit_card_id"], name: "index_transactions_on_credit_card_id"
    t.index ["income_id"], name: "index_transactions_on_income_id"
    t.index ["source_message_id"], name: "index_transactions_on_source_message_id", unique: true, where: "(source_message_id IS NOT NULL)"
    t.index ["transfer_to_bank_account_id"], name: "index_transactions_on_transfer_to_bank_account_id"
    t.index ["transfer_to_credit_card_id"], name: "index_transactions_on_transfer_to_credit_card_id"
    t.index ["whatsapp_message_id"], name: "index_transactions_on_whatsapp_message_id"
    t.check_constraint "installment_number IS NULL OR commitment_id IS NOT NULL", name: "transactions_installment_requires_commitment"
    t.check_constraint "num_nonnulls(bank_account_id, credit_card_id) <= 1", name: "transactions_one_instrument_max"
    t.check_constraint "num_nonnulls(transfer_to_bank_account_id, transfer_to_credit_card_id) <= 1", name: "transactions_one_transfer_dest_max"
    t.check_constraint "transfer_to_bank_account_id IS NULL AND transfer_to_credit_card_id IS NULL OR direction::text = 'transfer'::text", name: "transactions_transfer_dest_only_on_transfer"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.bigint "default_credit_card_id"
    t.citext "email_address", null: false
    t.string "locale", default: "pt-BR", null: false
    t.string "name"
    t.datetime "onboarded_at"
    t.string "password_digest"
    t.string "pending_invitation_token"
    t.string "phone"
    t.datetime "phone_verified_at"
    t.datetime "updated_at", null: false
    t.string "whatsapp_id"
    t.string "whatsapp_jid"
    t.string "whatsapp_verification_code"
    t.index ["default_credit_card_id"], name: "index_users_on_default_credit_card_id"
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
    t.bigint "account_id"
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
    t.string "type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "wa_message_id"
    t.index ["account_id"], name: "index_whatsapp_messages_on_account_id"
    t.index ["transaction_id"], name: "index_whatsapp_messages_on_transaction_id"
    t.index ["user_id", "created_at"], name: "index_whatsapp_messages_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_whatsapp_messages_on_user_id"
    t.index ["wa_message_id"], name: "index_whatsapp_messages_on_wa_message_id", unique: true, where: "(wa_message_id IS NOT NULL)"
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bank_accounts", "accounts"
  add_foreign_key "bank_accounts", "institutions"
  add_foreign_key "bank_accounts", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "bank_accounts", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "bank_accounts", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "card_bill_financings", "accounts"
  add_foreign_key "card_bill_financings", "card_bills"
  add_foreign_key "card_bill_financings", "transactions", column: "down_payment_transaction_id", on_delete: :nullify
  add_foreign_key "card_bill_financings", "users", column: "created_by_id"
  add_foreign_key "card_bill_financings", "users", column: "updated_by_id"
  add_foreign_key "card_bills", "accounts"
  add_foreign_key "card_bills", "credit_cards"
  add_foreign_key "card_bills", "users", column: "created_by_id"
  add_foreign_key "card_bills", "users", column: "updated_by_id"
  add_foreign_key "categories", "accounts"
  add_foreign_key "categories", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "categories", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "categories", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "commitments", "accounts"
  add_foreign_key "commitments", "bank_accounts"
  add_foreign_key "commitments", "bank_accounts", column: "transfer_to_bank_account_id"
  add_foreign_key "commitments", "categories"
  add_foreign_key "commitments", "credit_cards"
  add_foreign_key "commitments", "goals", on_delete: :nullify
  add_foreign_key "commitments", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "commitments", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "commitments", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "credit_cards", "accounts"
  add_foreign_key "credit_cards", "credit_cards", column: "parent_card_id"
  add_foreign_key "credit_cards", "institutions"
  add_foreign_key "credit_cards", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "credit_cards", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "credit_cards", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "document_imports", "accounts"
  add_foreign_key "document_imports", "bank_accounts"
  add_foreign_key "document_imports", "credit_cards"
  add_foreign_key "document_imports", "institutions"
  add_foreign_key "document_imports", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "document_imports", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "goal_checks", "accounts"
  add_foreign_key "goal_checks", "goals"
  add_foreign_key "goal_conversations", "accounts"
  add_foreign_key "goal_conversations", "goals"
  add_foreign_key "goal_conversations", "users"
  add_foreign_key "goals", "accounts"
  add_foreign_key "goals", "bank_accounts", column: "initial_saved_bank_account_id", on_delete: :nullify
  add_foreign_key "goals", "bank_accounts", on_delete: :nullify
  add_foreign_key "goals", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "goals", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "incomes", "accounts"
  add_foreign_key "incomes", "bank_accounts"
  add_foreign_key "incomes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "incomes", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "incomes", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "invitations", "accounts"
  add_foreign_key "invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "notifications", "accounts"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_identities", "users"
  add_foreign_key "push_devices", "sessions"
  add_foreign_key "push_devices", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "bank_accounts"
  add_foreign_key "transactions", "bank_accounts", column: "transfer_to_bank_account_id"
  add_foreign_key "transactions", "card_bills"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "commitments"
  add_foreign_key "transactions", "credit_cards"
  add_foreign_key "transactions", "credit_cards", column: "transfer_to_credit_card_id"
  add_foreign_key "transactions", "incomes"
  add_foreign_key "transactions", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "transactions", "users", column: "deleted_by_id", on_delete: :nullify
  add_foreign_key "transactions", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "transactions", "whatsapp_messages"
  add_foreign_key "users", "credit_cards", column: "default_credit_card_id"
  add_foreign_key "whatsapp_messages", "accounts"
  add_foreign_key "whatsapp_messages", "transactions"
  add_foreign_key "whatsapp_messages", "users"
end
