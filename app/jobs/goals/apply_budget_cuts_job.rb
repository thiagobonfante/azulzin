module Goals
  # Daily sweep (recurring.yml `goals_apply_budget_cuts`, 10:00 UTC — an hour before the 11:00
  # checks, so the month's first Budgets::Check already sees the written budgets). Daily, not
  # monthly: starts_on is per-goal and a missed 1st-of-month run must self-heal; the
  # budgets_applied_at guard makes re-runs no-ops. Dev has no recurring scheduler — run
  # `Goals::ApplyBudgetCutsJob.perform_now` from the console (docs/goals.md).
  class ApplyBudgetCutsJob < ApplicationJob
    queue_as :default

    def perform
      applied = 0
      Goal.active.where(budgets_applied_at: nil).where(starts_on: ..Recompute.current_month)
          .includes(:account)
          .find_each { |goal| applied += 1 if ApplyBudgetCuts.call(goal) }
      Rails.logger.info("goals_apply_budget_cuts: applied #{applied} goals")
    end
  end
end
