module Goals
  # Abandon a goal (.plans/goals 02 §3): status flip, never a destroy — "guardado continua
  # guardado" (the posted transfers stay). The savings Commitment is archived so it stops denting
  # sobra and firing reminders; its past payments keep their commitment_id.
  class Abandon
    def self.call(goal)
      ActiveRecord::Base.transaction do
        goal.update!(status: "abandoned", abandoned_at: Time.current)
        goal.commitments.savings.active.update_all(archived_at: Time.current, updated_at: Time.current)
      end
    end
  end
end
