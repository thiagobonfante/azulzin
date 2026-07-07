# The notification spine (up-tier 01 §1): one ledger row is the dashboard alert AND the
# per-channel send-claim AND the dedup key — the goal_checks shape, generalized. The unique
# index is the idempotency referee (same pattern as index_transactions_commitment_paid_once).
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user,    null: false, foreign_key: true   # the recipient (per-member, has phone + locale)
      t.references :account, null: false, foreign_key: true   # the financial context the alert is about
      t.string  :kind, null: false                            # bill_due | card_bill | … (Notifications::KINDS)
      t.string  :subject_type                                 # "Commitment" | "CreditCard" | "Income" | "Category" | nil
      t.bigint  :subject_id                                   # the row it's about; nil for summaries
      t.date    :period_key, null: false                      # the dedup axis, SP-time (due date / billing month / week)
      t.jsonb   :payload, null: false, default: {}            # pre-computed amounts/labels — BOTH renderers template from this
      t.datetime :whatsapp_sent_at                            # atomic WA send claim (fail-closed); nil = not pushed
      t.datetime :dismissed_at                                # dashboard dismissal
      t.timestamps
    end
    # THE idempotency key. nulls_not_distinct so subject-less kinds (summaries: both
    # subject columns NULL) are refereed by the DB too — default PG NULL-distinct
    # semantics would let concurrent summary rows slip past the unique index.
    add_index :notifications, [ :user_id, :kind, :subject_type, :subject_id, :period_key ],
              unique: true, nulls_not_distinct: true, name: "index_notifications_dedup"
    add_index :notifications, [ :user_id, :dismissed_at ]              # dashboard surface query
  end
end
