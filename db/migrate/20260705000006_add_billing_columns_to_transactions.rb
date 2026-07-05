class AddBillingColumnsToTransactions < ActiveRecord::Migration[8.1]
  def up
    add_column :transactions, :billing_month, :date                                  # universal month key (01 §2)
    add_column :transactions, :billing_month_manual, :boolean, null: false, default: false  # sticky manual move (R2)
    add_column :transactions, :installment_number, :integer                          # "parcela 3/10" (R11)
    add_reference :transactions, :category,   foreign_key: true                      # nullable (R6)
    add_reference :transactions, :commitment, foreign_key: true                      # nullable (R10/R11 link)
    add_reference :transactions, :income,     foreign_key: true                      # nullable (R1 receipt link)
    add_reference :transactions, :transfer_to_bank_account,
                  foreign_key: { to_table: :bank_accounts }                          # nullable (R5 destination)

    # Backfill every existing row to its calendar month, then lock NOT NULL.
    execute "UPDATE transactions SET billing_month = date_trunc('month', occurred_on)::date"
    change_column_null :transactions, :billing_month, false

    add_index :transactions, [ :user_id, :billing_month ]                            # the hub's one predicate
    add_index :transactions, [ :credit_card_id, :billing_month ],
              where: "credit_card_id IS NOT NULL",
              name: "index_transactions_on_card_and_billing_month"                   # §6 bill aggregates

    # Paid-at-most-once per (commitment, month); rejected rows free the slot (no callback).
    # Card parcels (installment_number + credit_card_id) are EXEMPT — R2's manual move may
    # legitimately co-locate two parcels of one plan on the same fatura.
    add_index :transactions, [ :commitment_id, :billing_month ], unique: true,
              where: "commitment_id IS NOT NULL AND status = 'posted'" \
                     " AND (installment_number IS NULL OR credit_card_id IS NULL)",
              name: "index_transactions_commitment_paid_once"

    add_check_constraint :transactions,
      "transfer_to_bank_account_id IS NULL OR direction = 'transfer'",
      name: "transactions_transfer_dest_only_on_transfer"
    add_check_constraint :transactions,
      "installment_number IS NULL OR commitment_id IS NOT NULL",
      name: "transactions_installment_requires_commitment"
  end

  def down
    remove_check_constraint :transactions, name: "transactions_installment_requires_commitment"
    remove_check_constraint :transactions, name: "transactions_transfer_dest_only_on_transfer"
    remove_index :transactions, name: "index_transactions_commitment_paid_once"
    remove_index :transactions, name: "index_transactions_on_card_and_billing_month"
    remove_index :transactions, column: [ :user_id, :billing_month ]
    remove_reference :transactions, :transfer_to_bank_account
    remove_reference :transactions, :income
    remove_reference :transactions, :commitment
    remove_reference :transactions, :category
    remove_column :transactions, :installment_number
    remove_column :transactions, :billing_month_manual
    remove_column :transactions, :billing_month
  end
end
