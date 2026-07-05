class AddBillingFieldsToCreditCards < ActiveRecord::Migration[8.1]
  def change
    # vencimento (nullable — existing cards are legitimately unconfigured; billing_configured? keys on this)
    add_column :credit_cards, :bill_due_day, :integer
    # fechamento offset — NOT NULL DEFAULT 7, the BR market norm (09 P0 #5)
    add_column :credit_cards, :closing_offset_days, :integer, null: false, default: 7

    add_check_constraint :credit_cards, "bill_due_day BETWEEN 1 AND 31",
                         name: "credit_cards_bill_due_day_range"
    add_check_constraint :credit_cards, "closing_offset_days BETWEEN 0 AND 28",
                         name: "credit_cards_closing_offset_range"
  end
end
