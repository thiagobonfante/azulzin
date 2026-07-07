# Namespace for the notification spine (.plans/up-tier 01). KINDS is the declarative
# registry: adding a proactive notification later = registering a kind here + a scanner
# that produces Notification rows — delivery, consent, dedup, dashboard, quiet hours and
# ban-safety already exist in Notifications::Deliver, once.
module Notifications
  # kind => the NotificationPreference toggle that gates it (BOTH channels: dashboard and
  # WhatsApp). Each kind's copy lives under a per-channel namespace completed from
  # template_key: notifications.dashboard.<key> for the banner and
  # whatsapp.replies.notifications.<key> for the push (Phase 3).
  KINDS = {
    "bill_due"         => { toggle: "bill_reminders" },
    "bill_overdue"     => { toggle: "bill_reminders" },
    # card_bill is ONE kind with two sub-events — fatura closing and fatura due — that
    # Reminders::Scan discriminates via payload["event"]; template_key completes it into
    # card_closing / card_due for both renderers.
    "card_bill"        => { toggle: "bill_reminders" },
    "income_expected"  => { toggle: "bill_reminders" },
    "budget_warn"      => { toggle: "budget_alerts" },
    "budget_breach"    => { toggle: "budget_alerts" },
    "surplus_nudge"    => { toggle: "surplus_nudges" },
    "rightsize_budget" => { toggle: "surplus_nudges" },
    "weekly_summary"   => { toggle: "weekly_summary" },
    "monthly_summary"  => { toggle: "monthly_summary" }
  }.freeze

  # The per-kind template key BOTH renderers complete into their own namespace — the one
  # place the card_bill event-split convention lives (dashboard banner and WhatsApp push
  # must never disagree on which template a row renders).
  def self.template_key(notification)
    return notification.kind unless notification.kind == "card_bill"
    "card_#{notification.payload.fetch('event', 'due')}"
  end

  # Interpolation args from the payload snapshot, shared by both renderers (01 §1:
  # neither re-queries; a deleted subject still renders). Payloads carry integer cents
  # (any *_cents key) plus optionally a days count: money is formatted by the caller's
  # block at render time, in the viewer's locale — never baked into the snapshot
  # (amount_cents → %{amount}, spent_cents → %{spent}, …) — and days_until /
  # days_overdue drive pluralization ("vence hoje / amanhã / em N dias").
  def self.template_args(notification)
    payload = notification.payload.symbolize_keys
    args = payload.except(:days_until, :days_overdue, :event)
    payload.each_key do |key|
      next unless key.to_s.end_with?("_cents")
      args[key.to_s.delete_suffix("_cents").to_sym] = yield(args.delete(key))
    end
    if (days = payload[:days_until] || payload[:days_overdue])
      args[:count] = days
    end
    args
  end
end
