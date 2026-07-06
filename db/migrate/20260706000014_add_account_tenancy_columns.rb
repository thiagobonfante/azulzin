# Migration B of the tenancy cutover (.plans/multi-user, D2/D3, doc 05 §1.5/§2.3).
# Adds nullable account_id, RENAMES user_id -> created_by_id (attribution, FK re-pointed to
# ON DELETE SET NULL), and adds updated_by_id / deleted_at / deleted_by_id. All nullable at
# this stage; Migration D tightens account_id to NOT NULL after the backfill.
class AddAccountTenancyColumns < ActiveRecord::Migration[8.1]
  DOMAIN   = %i[bank_accounts credit_cards categories commitments incomes transactions document_imports].freeze
  SOFT_DEL = %i[bank_accounts credit_cards categories commitments incomes transactions].freeze

  def up
    DOMAIN.each do |table|
      add_reference table, :account, foreign_key: true, null: true   # NOT NULL in Migration D

      # user_id becomes attribution: rename, relax, re-point the FK to SET NULL.
      rename_column table, :user_id, :created_by_id
      change_column_null table, :created_by_id, true
      remove_foreign_key table, :users, column: :created_by_id
      add_foreign_key    table, :users, column: :created_by_id, on_delete: :nullify

      # index: false — never queried by updated_by (doc 05 §1.5); don't ship dead indexes.
      add_reference table, :updated_by, null: true, index: false,
                    foreign_key: { to_table: :users, on_delete: :nullify }
    end

    SOFT_DEL.each do |table|
      add_column    table, :deleted_at, :datetime
      add_reference table, :deleted_by, null: true, index: false,
                    foreign_key: { to_table: :users, on_delete: :nullify }
    end

    add_reference :whatsapp_messages, :account, foreign_key: true, null: true  # stays nullable forever
  end

  def down
    remove_reference :whatsapp_messages, :account, foreign_key: true

    SOFT_DEL.each do |table|
      remove_reference table, :deleted_by, foreign_key: { to_table: :users }
      remove_column    table, :deleted_at
    end

    DOMAIN.each do |table|
      remove_reference table, :updated_by, foreign_key: { to_table: :users }

      remove_foreign_key table, :users, column: :created_by_id
      add_foreign_key    table, :users, column: :created_by_id   # restore the original plain FK
      change_column_null table, :created_by_id, false
      rename_column table, :created_by_id, :user_id

      remove_reference table, :account, foreign_key: true
    end
  end
end
