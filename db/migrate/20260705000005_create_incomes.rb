class CreateIncomes < ActiveRecord::Migration[8.1]
  def change
    create_table :incomes do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :bank_account, null: false, foreign_key: true   # WHICH account receives it
      t.string   :name, null: false, limit: 80                     # "salário", "pensão" — user data, not i18n
      t.bigint   :amount_cents, null: false
      t.string   :schedule_kind, null: false, default: "fixed_day" # fixed_day | nth_business_day
      t.integer  :schedule_day,  null: false                       # 1..31 (clamped) or nth 1..10
      t.datetime :archived_at
      t.timestamps
    end
  end
end
