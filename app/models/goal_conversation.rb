# Multi-turn state for the WhatsApp goal-creation chat (round 3 decision 8). One open
# conversation per sender (partial unique index), 24h TTL, passively expired — the job only
# routes replies through GoalConversation.open_for. `data` holds the collected slots
# (kind/name/target_cents/target_month/initial_saved_cents), the pending_slot, and the
# numbered-pick options in PROMPT order. The draft Goal is created at offer time and linked
# here so cancel/reject/expiry can destroy it (an invisible draft leaks the AI-session quota).
class GoalConversation < ApplicationRecord
  include AccountScoped

  TTL = 24.hours   # a goal chat is not a 60-min expense ask; product-tunable

  belongs_to :user
  belongs_to :goal, optional: true

  enum :status, {
    collecting:         "collecting",
    offered:            "offered",
    picking_caixinha:   "picking_caixinha",
    picking_source:     "picking_source",
    # Reorganizar (round 4): the replan chat rides the same one-open-per-user state row.
    replan_picking_goal: "replan_picking_goal",
    replan_offered:      "replan_offered",
    closed:             "closed"
  }, default: "collecting", validate: true

  # The single open goal chat for a sender (mirrors Transaction.open_ask_for).
  def self.open_for(user)
    where(user: user).where.not(status: "closed")
      .where("expires_at > ?", Time.current)
      .order(created_at: :desc).first
  end

  # Conditional transition (Transaction#guarded_update idiom): applies attrs only if the row
  # is still in one of `from_statuses` and returns whether it moved — a double "sim" matches
  # zero rows. update_all: one atomic UPDATE, no callbacks/validations.
  def guarded_transition(from_statuses, attrs)
    n = self.class.where(id: id, status: from_statuses)
             .update_all(attrs.merge(updated_at: Time.current))
    reload if n.positive?
    n.positive?
  end
end
