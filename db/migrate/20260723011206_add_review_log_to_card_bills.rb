class AddReviewLogToCardBills < ActiveRecord::Migration[8.1]
  def change
    # What the current conferência DID (moves/adjustments) — so cancel can roll it back.
    add_column :card_bills, :review_log, :jsonb, default: [], null: false
  end
end
