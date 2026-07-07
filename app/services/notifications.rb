# Namespace for the notification spine (.plans/up-tier 01). KINDS is the declarative
# registry: adding a proactive notification later = registering a kind here + a scanner
# that produces Notification rows — delivery, consent, dedup, dashboard, quiet hours and
# ban-safety already exist in Notifications::Deliver, once.
module Notifications
  # kind => the NotificationPreference toggle that gates it (BOTH channels: dashboard and
  # WhatsApp) and the i18n key the dashboard banner templates from the payload snapshot.
  # Phase 3 adds the WhatsApp channel, templated from whatsapp.replies.notifications.<kind>.
  KINDS = {
    "bill_due"         => { toggle: "bill_reminders",  i18n: "notifications.dashboard.bill_due" },
    "bill_overdue"     => { toggle: "bill_reminders",  i18n: "notifications.dashboard.bill_overdue" },
    # card_bill is ONE kind with two sub-events — fatura closing and fatura due — that
    # Reminders::Scan discriminates via payload["event"] ("closing" | "due"). The value
    # here is the prefix NotificationsHelper completes into card_closing / card_due.
    "card_bill"        => { toggle: "bill_reminders",  i18n: "notifications.dashboard.card" },
    "income_expected"  => { toggle: "bill_reminders",  i18n: "notifications.dashboard.income_expected" },
    "budget_warn"      => { toggle: "budget_alerts",   i18n: "notifications.dashboard.budget_warn" },
    "budget_breach"    => { toggle: "budget_alerts",   i18n: "notifications.dashboard.budget_breach" },
    "surplus_nudge"    => { toggle: "surplus_nudges",  i18n: "notifications.dashboard.surplus_nudge" },
    "rightsize_budget" => { toggle: "surplus_nudges",  i18n: "notifications.dashboard.rightsize_budget" },
    "weekly_summary"   => { toggle: "weekly_summary",  i18n: "notifications.dashboard.weekly_summary" },
    "monthly_summary"  => { toggle: "monthly_summary", i18n: "notifications.dashboard.monthly_summary" }
  }.freeze
end
