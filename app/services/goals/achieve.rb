module Goals
  # Conclude a goal (.plans/goals 07 §3): idempotent flip to achieved, archiving the savings
  # commitment (the promise is kept). celebrated_at is left nil so the next visit fires the in-app
  # celebration exactly once. Safe to call on every render — the guarded update no-ops if not active.
  class Achieve
    def self.call(goal)
      return false unless goal.active?
      flipped = Goal.where(id: goal.id, status: "active")
                    .update_all(status: "achieved", achieved_at: Time.current, updated_at: Time.current)
                    .positive?
      return false unless flipped
      goal.commitments.savings.active.update_all(archived_at: Time.current, updated_at: Time.current)
      goal.reload
      true
    end
  end
end
