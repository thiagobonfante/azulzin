# Link a goal to its "pay yourself first" savings commitment (.plans/goals 07 §1.2). Activation
# creates one kind: "savings" Commitment whose source account is bank_account_id and whose
# destination caixinha lives on the goal. One ACTIVE savings commitment per goal (partial unique
# index); abandoned/achieved goals archive the commitment ("guardado continua guardado").
class AddGoalToCommitments < ActiveRecord::Migration[8.1]
  def change
    # Nullify on goal delete (house pattern) so a draft-goal discard never trips the FK; the app
    # path archives the commitment on abandon/achieve rather than deleting the goal.
    add_reference :commitments, :goal, null: true, foreign_key: { on_delete: :nullify }, index: true

    add_index :commitments, :goal_id, unique: true,
      where: "goal_id IS NOT NULL AND archived_at IS NULL AND deleted_at IS NULL",
      name: "index_commitments_one_active_per_goal"
  end
end
