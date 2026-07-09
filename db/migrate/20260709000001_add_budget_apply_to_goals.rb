# State for writing a goal's plan cuts into the standing category budgets at starts_on (round 3
# decision 2): budgets_applied_at nil = not yet applied (the daily sweep's idempotency guard);
# previous_budgets maps category_id (string) => pre-apply monthly_budget_cents (or null — the
# apply created the budget) so Abandon/Achieve can revert.
class AddBudgetApplyToGoals < ActiveRecord::Migration[8.1]
  def change
    add_column :goals, :budgets_applied_at, :datetime
    add_column :goals, :previous_budgets, :jsonb, null: false, default: {}
  end
end
