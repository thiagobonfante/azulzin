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

ActiveRecord::Schema[8.1].define(version: 2026_07_04_120004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "bank_accounts", force: :cascade do |t|
    t.string "account_number"
    t.string "agency"
    t.bigint "balance_cents"
    t.datetime "created_at", null: false
    t.bigint "institution_id", null: false
    t.string "nickname"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["institution_id"], name: "index_bank_accounts_on_institution_id"
    t.index ["user_id"], name: "index_bank_accounts_on_user_id"
  end

  create_table "credit_cards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "credit_limit_cents"
    t.bigint "current_bill_cents"
    t.bigint "institution_id", null: false
    t.string "nickname"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["institution_id"], name: "index_credit_cards_on_institution_id"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
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

  create_table "users", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.citext "email_address", null: false
    t.string "locale", default: "pt-BR", null: false
    t.string "name"
    t.datetime "onboarded_at"
    t.string "password_digest"
    t.string "phone"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "bank_accounts", "institutions"
  add_foreign_key "bank_accounts", "users"
  add_foreign_key "credit_cards", "institutions"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "oauth_identities", "users"
  add_foreign_key "sessions", "users"
end
