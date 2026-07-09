# WhatsApp conversational goal creation (round 3 P6): durable multi-turn state. The txn-ask
# store can't host a goal chat (asks live ON transaction rows) and a partial Goal can't
# persist (goals NOT NULLs + target_cents > 0 check), so state gets its own table. One open
# conversation per sender, 24h TTL; the draft Goal is linked once created at offer time.
class CreateGoalConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :goal_conversations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :goal, null: true, foreign_key: true    # the draft, created at offer time
      t.string :status, null: false, default: "collecting"
      t.jsonb :data, null: false, default: {}              # slots + pending_slot + pick options
      t.datetime :expires_at, null: false
      t.timestamps
    end
    # The single-open-conversation invariant (mirrors Transaction.open_ask_for's single ask).
    add_index :goal_conversations, :user_id, unique: true, where: "status <> 'closed'",
              name: "index_goal_conversations_one_open_per_user"
  end
end
