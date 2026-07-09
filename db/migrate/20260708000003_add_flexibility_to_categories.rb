# Cached per-category flexibility for goal trims (.plans/goals 01 §1 tier-2). "flexible" |
# "essential" | nil (unresolved). Populated by the seeded-name map at analysis time (free) and,
# from Phase 4, by the batched LLM classifier — classification is paid once per category, ever.
class AddFlexibilityToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :flexibility, :string
  end
end
