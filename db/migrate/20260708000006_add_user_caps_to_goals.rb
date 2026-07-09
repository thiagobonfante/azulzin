# The household's own orçamento choices from the Diagnóstico sliders — { category_id => cap_cents }.
# Draft-time only input to PlanBuilder (fixed cuts); the chosen plan's cuts remain the frozen truth.
class AddUserCapsToGoals < ActiveRecord::Migration[8.1]
  def change
    add_column :goals, :user_caps, :jsonb, null: false, default: {}
  end
end
