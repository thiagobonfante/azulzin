# One weekly guardian snapshot per goal per ISO week (.plans/goals 03). Written by the Monday
# check job; the unique [goal_id, period_start] index is the idempotency referee. Holds only the
# deterministic facts — alert dedupe/dismissal live on the notification spine (06 §2). Findings is
# a machine-readable jsonb array both the dashboard and (later) WhatsApp render from the same keys.
class GoalCheck < ApplicationRecord
  include MoneyColumns
  include AccountScoped

  money_column :expected, :actual

  belongs_to :goal

  enum :status,
       { on_track: "on_track", at_risk: "at_risk", off_track: "off_track", insufficient_data: "insufficient_data" },
       validate: true

  validates :period_start, presence: true

  scope :latest_first, -> { order(period_start: :desc) }
end
