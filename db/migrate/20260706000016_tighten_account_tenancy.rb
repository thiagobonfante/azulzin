# Migration D of the tenancy cutover (.plans/multi-user, D2/D3, doc 05 §2.4). Tightens
# account_id to NOT NULL (backfill done in C) and swaps the per-user indexes to per-account,
# adding the soft-delete conditions where the index law requires them.
class TightenAccountTenancy < ActiveRecord::Migration[8.1]
  DOMAIN = %i[bank_accounts credit_cards categories commitments incomes transactions document_imports].freeze

  def up
    DOMAIN.each { |table| change_column_null table, :account_id, false }

    # (1) Categories uniqueness: per-user -> per-account, soft-delete-aware (D2 + D8).
    remove_index :categories, name: "index_categories_on_created_by_id_and_name"
    add_index    :categories, %i[account_id name], unique: true,
                 where: "deleted_at IS NULL",
                 name: "index_categories_on_account_id_and_name"

    # (2) Import dedupe: per-user -> per-account (same status condition, NO deleted_at).
    remove_index :document_imports, name: "index_document_imports_dedupe_checksum"
    add_index    :document_imports, %i[account_id checksum], unique: true,
                 where: "status NOT IN ('dismissed', 'failed')",
                 name: "index_document_imports_dedupe_checksum"

    # (3) Hot-path composites re-rooted on account (queries now filter by account_id).
    remove_index :transactions, name: "index_transactions_on_created_by_id_and_billing_month"
    add_index    :transactions, %i[account_id billing_month]
    remove_index :transactions, name: "index_transactions_on_created_by_id_and_status"
    add_index    :transactions, %i[account_id status]
    remove_index :commitments,  name: "index_commitments_on_created_by_id_and_kind"
    add_index    :commitments,  %i[account_id kind]
    remove_index :document_imports, name: "index_document_imports_on_created_by_id_and_status"
    add_index    :document_imports, %i[account_id status]

    # (4) Paid-once gains the soft-delete condition (doc 05 §2.4).
    remove_index :transactions, name: "index_transactions_commitment_paid_once"
    add_index :transactions, %i[commitment_id billing_month], unique: true,
              name: "index_transactions_commitment_paid_once",
              where: "commitment_id IS NOT NULL AND status = 'posted' " \
                     "AND (installment_number IS NULL OR credit_card_id IS NULL) " \
                     "AND deleted_at IS NULL"
  end

  def down
    remove_index :transactions, name: "index_transactions_commitment_paid_once"
    add_index :transactions, %i[commitment_id billing_month], unique: true,
              name: "index_transactions_commitment_paid_once",
              where: "commitment_id IS NOT NULL AND status = 'posted' " \
                     "AND (installment_number IS NULL OR credit_card_id IS NULL)"

    remove_index :document_imports, name: "index_document_imports_on_account_id_and_status"
    add_index    :document_imports, %i[created_by_id status],
                 name: "index_document_imports_on_created_by_id_and_status"
    remove_index :commitments, name: "index_commitments_on_account_id_and_kind"
    add_index    :commitments, %i[created_by_id kind],
                 name: "index_commitments_on_created_by_id_and_kind"
    remove_index :transactions, name: "index_transactions_on_account_id_and_status"
    add_index    :transactions, %i[created_by_id status],
                 name: "index_transactions_on_created_by_id_and_status"
    remove_index :transactions, name: "index_transactions_on_account_id_and_billing_month"
    add_index    :transactions, %i[created_by_id billing_month],
                 name: "index_transactions_on_created_by_id_and_billing_month"

    remove_index :document_imports, name: "index_document_imports_dedupe_checksum"
    add_index    :document_imports, %i[created_by_id checksum], unique: true,
                 where: "status NOT IN ('dismissed', 'failed')",
                 name: "index_document_imports_dedupe_checksum"

    remove_index :categories, name: "index_categories_on_account_id_and_name"
    add_index    :categories, %i[created_by_id name], unique: true,
                 name: "index_categories_on_created_by_id_and_name"

    DOMAIN.each { |table| change_column_null table, :account_id, true }
  end
end
