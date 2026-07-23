class CreateCardBillFinancings < ActiveRecord::Migration[8.0]
  def change
    # A contracted parcelamento de fatura (CMN 4.549: after one rotativo cycle the bank
    # offers to split the remainder into N fixed parcels). One per bill; the bank's own
    # numbers are stored verbatim — parcels are DERIVED lines on future bills (the
    # Carryover spine), never transaction rows, so destroying the row is the rollback.
    create_table :card_bill_financings do |t|
      t.references :account,   null: false, foreign_key: true
      t.references :card_bill, null: false, foreign_key: true, index: { unique: true }
      t.integer :installments_count, null: false
      t.bigint  :installment_cents,  null: false   # the bank's fixed parcela
      t.bigint  :financed_cents,     null: false   # the remainder that was parceled
      t.date    :first_charge_month, null: false   # parcel 1's billing month
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
