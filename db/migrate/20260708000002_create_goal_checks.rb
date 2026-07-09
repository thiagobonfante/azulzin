# Weekly guardian ledger (.plans/goals 01 §2, slimmed by 06 §1). One row per goal per ISO week
# (SP time). The unique [goal_id, period_start] index is THE idempotency referee — a re-run's
# duplicate create! raises RecordNotUnique and is rescued to load-and-return, never clobbering.
# Alert dedupe/dismissal live on the notification spine now (06 §2), so no user_id/alerted_at/
# dismissed_at here — just the deterministic check facts. account_id enables account-wide reads.
class CreateGoalChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :goal_checks do |t|
      t.references :goal,    null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true

      t.date    :period_start, null: false                 # ISO-week Monday, SP time
      t.string  :status,       null: false                 # on_track | at_risk | off_track | insufficient_data
      t.bigint  :expected_cents, null: false, default: 0   # cumulative expected saved by check date
      t.bigint  :actual_cents,   null: false, default: 0   # cumulative actual guardado
      t.jsonb   :findings, null: false, default: []        # structured drift facts (03 §3)

      t.timestamps
    end

    add_index :goal_checks, [ :goal_id, :period_start ], unique: true   # THE idempotency key
  end
end
