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
    # Fatura closing and fatura due are two REAL kinds (not one kind + a payload
    # discriminator): the dedup key is (kind, subject, period_key), and a closing date
    # can land exactly on the previous month's due date — distinct kinds keep both.
    "card_closing"     => { toggle: "bill_reminders" },
    "card_due"         => { toggle: "bill_reminders" },
    "income_expected"  => { toggle: "bill_reminders" },
    "budget_warn"      => { toggle: "budget_alerts" },
    "budget_breach"    => { toggle: "budget_alerts" },
    "surplus_nudge"    => { toggle: "surplus_nudges" },
    "rightsize_budget" => { toggle: "surplus_nudges" },
    "weekly_summary"   => { toggle: "weekly_summary" },
    "monthly_summary"  => { toggle: "monthly_summary" }
  }.freeze

  # The digest kinds carry structured payloads (top_categories, upcoming, budget counts)
  # whose composite lines are assembled at render time — see template_args below.
  SUMMARY_KINDS = %w[weekly_summary monthly_summary].freeze

  # The per-kind template key BOTH renderers complete into their own namespace (dashboard
  # banner and WhatsApp push must never disagree on which template a row renders). Every
  # kind maps 1:1 to its template today; the seam stays for a future kind that doesn't.
  def self.template_key(notification) = notification.kind

  # Interpolation args from the payload snapshot, shared by both renderers (01 §1:
  # neither re-queries; a deleted subject still renders). Payloads carry integer cents
  # (any *_cents key) plus optionally a days count: money is formatted by the caller's
  # block at render time, in the viewer's locale — never baked into the snapshot
  # (amount_cents → %{amount}, spent_cents → %{spent}, …) — and days_until /
  # days_overdue drive pluralization ("vence hoje / amanhã / em N dias").
  #
  # Summary kinds add composite lines (spent/cats, upcoming, budget) assembled by
  # Summaries::Lines from the payload's structured keys — also at render time, also in
  # the viewer's locale, because they mix user data with localized words and money.
  def self.template_args(notification, &money)
    payload = notification.payload.symbolize_keys
    return summary_args(payload, &money) if SUMMARY_KINDS.include?(notification.kind)
    args = payload.except(:days_until, :days_overdue)
    payload.each_key do |key|
      next unless key.to_s.end_with?("_cents")
      args[key.to_s.delete_suffix("_cents").to_sym] = yield(args.delete(key))
    end
    if (days = payload[:days_until] || payload[:days_overdue])
      args[:count] = days
    end
    args
  end

  # A digest payload is structured keys (consumed by Summaries::Lines) + *_cents figures
  # by construction — nothing else — so every remaining key takes the money transform.
  def self.summary_args(payload, &money)
    payload.except(*Summaries::Lines::STRUCTURED_KEYS)
           .to_h { |key, cents| [ key.to_s.delete_suffix("_cents").to_sym, money.call(cents) ] }
           .merge(Summaries::Lines.args(payload, &money))
  end
end
