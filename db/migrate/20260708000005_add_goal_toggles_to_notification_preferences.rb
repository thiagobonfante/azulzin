# Per-member consent toggles for the goals notification kinds (.plans/goals 06 §2, 07 §3).
# goal_alerts (drift) is opt-IN like the up-tier proactive kinds' WhatsApp posture; goal_achieved
# (celebrations) is opt-OUT — "celebrate loudly, correct quietly". Both gate the WhatsApp push via
# Notifications::Deliver; the dashboard banner is free (the goals scanner records regardless).
class AddGoalTogglesToNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_preferences, :goal_alerts,   :boolean, null: false, default: false
    add_column :notification_preferences, :goal_achieved, :boolean, null: false, default: true
  end
end
