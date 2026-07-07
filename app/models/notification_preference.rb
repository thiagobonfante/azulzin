# Per-user consent + toggles for the notification spine (.plans/up-tier 01 §2). Created
# lazily by User#notification_prefs — no backfill. `whatsapp_consent` is the ONE deliberate
# switch that turns azulzin proactive on WhatsApp (ADR 0011): phone_verified? is ownership,
# not consent. Per-kind toggles gate both channels (dashboard included).
class NotificationPreference < ApplicationRecord
  belongs_to :user

  validates :bill_reminder_lead_days, numericality: { only_integer: true, in: 0..7 }
  validates :quiet_hours_start, :quiet_hours_end,
            numericality: { only_integer: true, in: 0..23 }   # SP-time hours
  validates :budget_warn_percent, :budget_breach_percent,
            numericality: { only_integer: true, in: 1..200 }
end
