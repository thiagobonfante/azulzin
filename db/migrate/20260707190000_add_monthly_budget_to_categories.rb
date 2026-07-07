# One standing monthly limit per category (up-tier 03 §1, D3): nil = no budget (the
# default; most categories). It's both the "prevê" and the "quer ficar" — a single number
# the household owns; per-month overrides are deferred.
class AddMonthlyBudgetToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :monthly_budget_cents, :bigint
  end
end
