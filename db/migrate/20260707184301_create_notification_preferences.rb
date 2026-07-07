# Per-user consent + toggles for the notification spine (up-tier 01 §2). Typed columns
# (house style over a jsonb blob). Created lazily (User#notification_prefs) — no backfill.
class CreateNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      # channel consent — phone_verified? is ownership, NOT consent (ADR 0011)
      t.boolean :whatsapp_consent, null: false, default: false
      # per-kind toggles (gate BOTH channels; default on for the free dashboard surface)
      t.boolean :bill_reminders,   null: false, default: true
      t.boolean :budget_alerts,    null: false, default: true
      t.boolean :surplus_nudges,   null: false, default: true
      t.boolean :weekly_summary,   null: false, default: false   # summaries are pure push → opt-in
      t.boolean :monthly_summary,  null: false, default: false
      # tuning
      t.integer :bill_reminder_lead_days, null: false, default: 1    # 0..7, validated
      t.integer :quiet_hours_start, null: false, default: 21         # SP hour; no WA push 21:00–08:00
      t.integer :quiet_hours_end,   null: false, default: 8
      t.integer :budget_warn_percent,   null: false, default: 80     # user-tunable alert bands…
      t.integer :budget_breach_percent, null: false, default: 100    # …shared with goals when it lands
      t.datetime :wa_intro_sent_at                                   # first-push opt-out footer shown once (Phase 3)
      t.timestamps
    end
  end
end
