class CreateBcbRates < ActiveRecord::Migration[8.0]
  def change
    # BCB average card rates (.plans/credit-cards 02 §2), cached daily. A table (not
    # Rails.cache) because "last known rate" must survive restarts and BCB outages — and
    # it is the audit trail for "why did we show 15,09%".
    create_table :bcb_rates do |t|
      t.string :kind, null: false                            # rotativo | parcelamento
      t.decimal :monthly_rate, precision: 8, scale: 4, null: false
      t.date :reference_month, null: false
      t.datetime :fetched_at, null: false
      t.timestamps

      t.index [ :kind, :reference_month ], unique: true
    end
  end
end
