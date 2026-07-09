module Goals
  # Enqueued at goal creation (and re-analysis) — never in-request, so Screen 2 renders instantly on
  # template notes and the polished notes land on the next view (.plans/goals 04 §1). The session
  # call cap (07 §2) is enforced increment-BEFORE-call: a transient-429 retry (handled inside the
  # OpenRouterClient) never grants an extra call, and quota burns fail-closed. A terminal failure is
  # absorbed by the Narrator (template notes stand) — no job-level retry, so no double increment.
  class NarrativeJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(goal_id)
      goal = Goal.find(goal_id)
      return unless goal.draft?
      # Not analyzed yet (a legacy draft) — nothing to narrate; bail BEFORE burning quota.
      return if goal.baseline["sufficiency"].blank?
      return if goal.ai_calls_count >= MAX_CALLS_PER_SESSION
      goal.increment!(:ai_calls_count)

      narratives = Goals::Narrator.call(goal)
      return if narratives.blank?
      goal.update!(baseline: goal.baseline.merge("narratives" => narratives))
    end
  end
end
