class CreateCardBills < ActiveRecord::Migration[8.0]
  def change
    # A CardBill exists only from closing time on (.plans/credit-cards 01 §1): the open
    # bill stays a query. Stores only what date math can't answer — the close/due
    # snapshots (a later config edit never rewrites settled history) and the bank's
    # numbers as informed by the user. Totals/status stay derived, never stored.
    create_table :card_bills do |t|
      t.references :account,     null: false, foreign_key: true
      t.references :credit_card, null: false, foreign_key: true, index: false
      t.date :billing_month, null: false
      t.date :closed_on,     null: false
      t.date :due_on,        null: false
      t.bigint :stated_total_cents
      t.bigint :stated_minimum_cents
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps

      # The close scan's idempotency key.
      t.index [ :credit_card_id, :billing_month ], unique: true
    end
  end
end
