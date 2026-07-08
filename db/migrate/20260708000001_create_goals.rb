# Financial goals ("Metas") — account-scoped household savings targets (.plans/goals 01 §2,
# reconciled by 06 §1 to account tenancy + 07 for the AI-session counter and celebration stamp).
# Goals READ the ledger and never write transactions; the chosen plan + frozen baseline are
# snapshotted as jsonb so a deleted category still renders. Two kinds: purchase (X by date D)
# and savings_rate (X more/month). Lifecycle is status, not soft-delete.
class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals do |t|
      t.references :account, null: false, foreign_key: true
      # Attribution (Attributable concern) — creator shown on shared accounts; nullify on user delete.
      t.references :created_by, null: true,
                   foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :updated_by, null: true, index: false,
                   foreign_key: { to_table: :users, on_delete: :nullify }

      t.string  :name,   null: false, limit: 80           # user text ("Carro"), not i18n
      t.string  :kind,   null: false                      # purchase | savings_rate
      t.string  :status, null: false, default: "draft"    # draft | active | achieved | abandoned

      t.bigint  :target_cents,        null: false             # price (purchase) or extra-per-month (savings_rate)
      t.date    :target_date                                  # purchase only (check below)
      t.bigint  :initial_saved_cents, null: false, default: 0
      t.bigint  :monthly_target_cents                         # frozen when a plan is chosen

      # linked caixinha; nil = all savings accounts. Nullify on delete: a deleted caixinha leaves
      # the goal alive, falling back to all-savings progress (.plans/goals 01 §3).
      t.references :bank_account, foreign_key: { on_delete: :nullify }
      t.date    :starts_on                                    # beginning_of_month of activation

      t.jsonb   :baseline, null: false, default: {}           # frozen analysis snapshot (01 §4)
      t.jsonb   :plan,     null: false, default: {}           # chosen plan snapshot (01 §5); immutable after activation

      t.integer  :ai_calls_count, null: false, default: 0     # per-session LLM call cap (07 §2)
      t.datetime :activated_at
      t.datetime :achieved_at
      t.datetime :abandoned_at
      t.datetime :celebrated_at                               # in-app celebration idempotency (07 §3)

      t.timestamps
    end

    add_check_constraint :goals,
      "(kind = 'purchase') = (target_date IS NOT NULL)", name: "goals_purchase_has_date"
    add_check_constraint :goals, "target_cents > 0", name: "goals_target_positive"
    add_check_constraint :goals, "initial_saved_cents >= 0", name: "goals_initial_saved_non_negative"
    add_check_constraint :goals,
      "monthly_target_cents IS NULL OR monthly_target_cents > 0", name: "goals_monthly_target_positive"

    add_index :goals, [:account_id, :status]
  end
end
