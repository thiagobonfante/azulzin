# 11. Proactive notifications: break reply-only, narrowly and opted-in

## Status

Accepted (2026-07-07) — founder-signed

## Context

`docs/whatsapp.md` decided the WhatsApp channel is **reply-only**: azulzin runs on wwebjs
(an unofficial client) with a single commercial number, and unsolicited outbound volume is
the classic ban trigger. Every message the product has ever sent was an answer to something
the user texted first.

The product now needs to speak first. Bill/due-date reminders, budget alerts, and periodic
summaries (the up-tier plan, `.plans/up-tier/`) are the most valuable layer azulzin doesn't
ship — the one place the WhatsApp channel and real family accounts compound into a pushed,
attributed, household nudge no incumbent can copy. All of them require an outbound message
nobody asked for in that moment. This is the first product reason to break reply-only, and
it is broken once, for *all* proactive kinds, through one spine: the `notifications` ledger
(alert + send-claim + dedup key in one row), `notification_preferences`, and the single
`Notifications::Deliver` send policy — never per-feature senders.

## Decision

**Proceed, narrowly.** Proactive WhatsApp push is allowed only through
`Notifications::Deliver`, with every mitigation on:

- **Consent is explicit and default-false.** `notification_preferences.whatsapp_consent`
  is an opt-in switch — `phone_verified?` proves number ownership, it is *not* consent.
  Per-kind toggles gate both channels; summaries are opt-in even on the dashboard.
  Consent is revocable in-app (the Avisos screen) and, from Phase 3, by texting "parar".
- **Volume is bounded.** Per-user daily cap of 3 pushes (`Deliver::DAILY_WA_CAP`, tunable);
  quiet hours (default 21:00–08:00 America/Sao_Paulo, user-tunable); once-per-period dedup
  enforced by a DB unique index (`index_notifications_dedup`), not application hope.
- **Sends are fail-closed and audited.** The atomic `whatsapp_sent_at` claim
  (`update_all(... whatsapp_sent_at: nil) == 1`) means a crash after claim loses a message
  but never duplicates one — a duplicate proactive push on a wwebjs number is worse than a
  missed one. Every send goes through `WhatsappReply.deliver`, so it is logged as an
  outbound `WhatsappMessage` and rendered in the recipient's locale; it rides the sidecar's
  existing anti-ban throttle (global 1.5s minimum + typing delay).
- **The dashboard soaks first.** Phases 0–2 ship the in-app alert surface with the send
  step inert — zero ban exposure while the scanners prove out. The first real push
  (Phase 3) also ships the WhatsApp-side stop command and the one-time opt-out footer on
  a user's first-ever push.

This posture covers every proactive kind — reminders, budget alerts, summaries, and the
future `goal_alert` — anything registered in `Notifications::KINDS` inherits it. This ADR
**supersedes** the goals plan's placeholder `0007-goals-proactive-whatsapp-and-ai.md`
(0007 is taken by the host split); goals' drift alerts become one more kind on this spine
when built.

## Consequences

- `docs/whatsapp.md`'s posture becomes "reply-only, plus opted-in proactive notifications";
  the amendment lands with Phase 3, when the first push can actually happen.
- A user who never flips the consent switch never receives a proactive WhatsApp message.
  The dashboard surface is the always-on baseline (free, in-app, per-kind revocable).
- New proactive features stop being ban-risk discussions: registering a kind + writing a
  scanner is the whole job; delivery, consent, dedup, quiet hours, and cap come for free.
- Ban risk is reduced, not eliminated — this is still an unofficial client. The
  single-session throttle remains the product-wide bottleneck; scaling the channel
  (multi-session / BSP migration) is a separate, later decision and is deliberately not
  designed around here.
