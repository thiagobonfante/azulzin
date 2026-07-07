class AddCategoryBackfillAtToAccounts < ActiveRecord::Migration[8.0]
  def change
    # When the last auto-categorization backfill run started: the 1-run-per-day cap,
    # the undo window anchor, and the ledger banner all key off it.
    add_column :accounts, :category_backfill_at, :datetime
  end
end
