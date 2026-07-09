module Goals
  # Conclude a goal (.plans/goals 07 §3): idempotent flip to achieved, archiving the savings
  # commitment (the promise is kept) and reverting applied budget cuts (round 3 decision 2 —
  # celebrate AND loosen; manual edits + other active goals' caps win inside RevertBudgetCuts).
  # celebrated_at is left nil so the next visit fires the in-app celebration exactly once. Safe
  # to call on every render — the guarded flip no-ops (and never double-reverts) if not active.
  class Achieve
    def self.call(goal)
      return false unless goal.active?
      ActiveRecord::Base.transaction do
        flipped = Goal.where(id: goal.id, status: "active")
                      .update_all(status: "achieved", achieved_at: Time.current, updated_at: Time.current)
                      .positive?
        raise ActiveRecord::Rollback unless flipped
        goal.commitments.savings.active.update_all(archived_at: Time.current, updated_at: Time.current)
        goal.reload
        RevertBudgetCuts.call(goal)
      end
      goal.achieved?
    end
  end
end
