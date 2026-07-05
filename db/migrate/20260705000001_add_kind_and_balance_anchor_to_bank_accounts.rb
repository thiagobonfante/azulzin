class AddKindAndBalanceAnchorToBankAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :bank_accounts, :kind, :string, null: false, default: "checking"  # checking | savings (R4)
    add_column :bank_accounts, :balance_anchored_at, :datetime                   # "balance was X at T" (derived balances)
    # Backfill the anchor so existing informed balances have a "known at" timestamp.
    execute "UPDATE bank_accounts SET balance_anchored_at = updated_at WHERE balance_cents IS NOT NULL"
  end

  def down
    remove_column :bank_accounts, :balance_anchored_at
    remove_column :bank_accounts, :kind
  end
end
