module Goals
  # Abandon a goal (.plans/goals 02 §3): status flip, never a destroy — "guardado continua
  # guardado" (the posted transfers stay). The savings Commitment is archived so it stops denting
  # sobra and firing reminders; its past payments keep their commitment_id.
  class Abandon
    def self.call(goal)
      return false unless goal.active?   # never revert an achieved goal, never touch a draft
      ActiveRecord::Base.transaction do
        flipped = Goal.where(id: goal.id, status: "active")
                      .update_all(status: "abandoned", abandoned_at: Time.current, updated_at: Time.current)
                      .positive?
        raise ActiveRecord::Rollback unless flipped
        goal.commitments.savings.active.update_all(archived_at: Time.current, updated_at: Time.current)
        goal.reload
      end
      goal.abandoned?
    end
  end
end
