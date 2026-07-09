module Goals
  # Writes an active goal's frozen plan cuts into the standing category budgets
  # (categories.monthly_budget_cents) once the goal's starts_on month arrives — the orçamento
  # screen then shows the cut value (round 3 decision 2). Idempotent: the budgets_applied_at
  # guard makes the daily sweep's re-runs no-ops. Per cut: min-tighten only (an already-tighter
  # budget stands), skip cap ≤ 0 (the > 0 validation — TrimCaps still alerts at 0) and
  # soft-deleted categories, CREATE budgets on unbudgeted categories, and snapshot the previous
  # value (or nil) into goals.previous_budgets for RevertBudgetCuts.
  class ApplyBudgetCuts
    def self.call(goal) = new(goal).call

    def initialize(goal)
      @goal = goal
    end

    def call
      return false unless @goal.active? && @goal.budgets_applied_at.nil?
      return false unless @goal.starts_on && @goal.starts_on <= Recompute.current_month

      applied = false
      ActiveRecord::Base.transaction do
        previous = write_caps
        # Guarded finalize — a concurrent sweep that already applied rolls this run back whole.
        finalized = Goal.where(id: @goal.id, budgets_applied_at: nil)
                        .update_all(budgets_applied_at: Time.current, previous_budgets: previous,
                                    updated_at: Time.current)
                        .positive?
        raise ActiveRecord::Rollback unless finalized
        applied = true
      end
      @goal.reload if applied
      applied
    end

    private
      # Tighten each cut category, returning { category_id(string) => previous cents or nil }.
      def write_caps
        (@goal.plan["cuts"] || []).each_with_object({}) do |cut, previous|
          category = @goal.account.categories.kept.find_by(id: cut["category_id"])
          next unless category
          cap = cut["cap_cents"].to_i
          next if cap <= 0
          next if category.monthly_budget_cents.present? && category.monthly_budget_cents <= cap
          previous[category.id.to_s] = category.monthly_budget_cents
          category.update_columns(monthly_budget_cents: cap, updated_at: Time.current)
        end
      end
  end
end
