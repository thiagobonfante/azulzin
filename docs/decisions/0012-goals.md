# 12. Goals ("Metas"): algorithm-first, AI-garnished, pay-yourself-first

## Status

Accepted (2026-07-08)

## Context

azulzin already captures every movement and knows the month's sobra. Goals turn that record
into forward motion: a named target, a plan derived from the household's *own* numbers, and a
weekly guardian that speaks only when behavior threatens the plan. The design question was how
much of this to hand to an LLM. The proactive-push posture is already settled by
[ADR 0011](0011-proactive-notifications.md); this ADR records the goals-specific engine, money,
and AI decisions. Goals ship on the account tenancy of [ADR 0009](0009-multi-user-accounts.md).

## Decision

**The engine is deterministic; the LLM only phrases.** Every number a goal shows or acts on is
SQL + BigDecimal over the ledger — integer cents, no Float ever (CI grep gate). `Goals::Analyzer`
snapshots per-category **medians** (never means) over the trailing 3 billing months into a frozen
`goals.baseline`; `Goals::PlanBuilder` derives 3 fixed personalities (leve / recomendado /
acelerado) with cents-exact trims, or three honest counter-offers when the goal doesn't close;
`Goals::Progress`/`Goals::Checker` judge pace guardado-vs-expected. Candidate plans are pure
functions of the frozen baseline — **recomputed on choose, never trusted from params**.

**The LLM appears in exactly two places, both at creation, both async, both with template
fallbacks** (the feature is complete at AI-budget zero): one batched call phrases all 3 coach
notes (a digit-mismatch guard rejects any invented money figure), and one closed-set call labels
custom categories flexible/essential, cached forever in `categories.flexibility`. **Weekly checks
and all WhatsApp copy are zero-LLM, by design** — a regression that adds an LLM call to the check
path fails the build (call-count assertion). AI cost is bounded *by construction*: ≤5 AI-assisted
sessions/account/billing-month and ≤3 narrative calls/session (`goals.ai_calls_count`,
increment-before-call so a retried 429 never grants an extra call), worst case < US$0.02/account/mo.

**Saving is the first bill, not the leftover ("pay yourself first").** Activating a goal creates a
real `kind: "savings"` Commitment. Goals still never write *transactions* — the commitment is a
schedule definition; the money moves only when the **user** pays the occurrence, producing an
ordinary posted **transfer** into the caixinha. An unpaid occurrence reduces sobra via
`MonthSummary#projected_guardado_cents` (excluded from spending); paying it moves the amount into
`guardado_cents` with **sobra invariant at pay time** — a named money-trap test. This buys due-date
reminders and the "guardei" WhatsApp loop from the shipped spine for free.

**Alerting rides the spine (ADR 0011), not a new sender.** `goal_alert` and `goal_achieved` are two
kinds on `Notifications::Deliver`. The dashboard banner is free (recorded on every alert-worthy
check); WhatsApp is opt-in per member (`goal_alerts`), gated by the household master consent, the
delta-gate + 14-day cooldown + weekly-one-per-user guard. A goal's category trim is a temporary
tightening of the **standing budget**, surfaced through the same `Budgets::Check` (effective limit =
`min(budget, trim cap)`), not a parallel cap path.

**Celebrate loudly, correct quietly.** A conclusion is **always** celebrated: an unconditional
in-app moment (idempotent off `celebrated_at`) plus a `goal_achieved` WhatsApp kind that is opt-OUT
(default true) — celebration is product, not notification. Drift, by contrast, is opt-in and
delta-gated. An infeasible goal is told "não fecha" with the numbers and three concrete ways out —
honest math is the product.

## Consequences

- Steady-state recurring AI cost is **R$ 0,00**; the dominant cost is Postgres, already paid for.
- The weekly sweep is a pure fan-out of indexed SELECTs, serialized per user in the shared
  `proactive_notify` concurrency group, so it stays race-free at scale.
- Editing an active plan is out of scope (abandon + recreate); goals never auto-move money or
  auto-edit; ≤5 active goals per account bound the fan-out and keep the product focused.
- Prod launch gating pins pt-BR; en-US keys ship complete and dark. The engine, money-trap tests,
  and tone contract are the load-bearing artifacts — see `.plans/goals/` and `docs/goals.md`.

## Round 3 addendum (2026-07-09)

Founder walkthrough fixes. Decisions recorded (detail in `docs/goals.md`):

- **Whole-real display.** Goals UI shows whole reais only: CEIL what the user is asked to save,
  FLOOR capacity/feasible figures and real ledger amounts — never overstate what the household
  can do or holds. Internal math and stored plans stay exact cents; `budget_*_goal` alerts keep
  2 decimals (sibling-alert consistency).
- **Next-month effectivity.** `starts_on` = next month begin for drafts and activation; expected
  pace is 0 through the gap month (eager transfers still count); checker grace covers the gap.
- **Budget write-through + revert.** At `starts_on` a daily sweep writes plan cuts into the
  standing category budgets (min-tighten only, creates missing budgets, snapshots previous
  values). Abandon AND achieve revert immediately — manual edits win, other active goals' caps
  respected. TrimCaps remains the month-aware alert floor.
- **Always-linked commitment, as parcels.** Activation requires caixinha + distinct source (no
  caixinha → blocked with a create-caixinha CTA). Purchase goals get a finite parcelado
  (`ends_on = starts_on >> (n − 1)`, N/total display); savings_rate stays open-ended. Legacy
  unlinked goals keep the Progress fallback. Hub label: "Guardar"; standalone savings
  commitments carry their own destination caixinha.
- **WA single-plan flow.** WhatsApp goal creation is a deterministic Q&A (one Extractor call to
  classify + seed, zero LLM after) presenting one recomendado plan — a deliberate deviation from
  the web's 3 personalities. WA drafts consume the AI-session quota but skip the narrator.

## Round 4 addendum (2026-07-09) — predictive guardian + Reorganizar

Founder ask: warn BEFORE goals break (household going red, next month's card faturas, budgets
raised over the goal's caps), on both channels, with an interaction that recomputes the goal —
and empathy when the miss had a good reason. Decisions (detail in `docs/goals.md`):

- **Predictive findings ride `goal_alert`.** No new notification kind or preference:
  `Goals::RiskScan` adds red_month / next_month_red / budget_raised / missed_month findings,
  selected per template by the existing payload seam (plus a `variant` tone fork). Red findings
  fire only when goal parcels sit in the red month, attach to the goal with the largest parcel
  (one alert per red month, never one per goal), and bypass grace and the 14-day cooldown —
  never the delta-gate (widened to finding+category+month), the weekly WA guard or the daily
  cap. The month projection is `MonthSummary`, so next month's faturas already include posted
  card spend billing forward.
- **Deterministic empathy.** The missed-month cause is computed, not phrased: lower income
  first, else the worst category overage vs the frozen baseline medians. Essential-category and
  income causes select the gentle copy ("imprevistos acontecem, sem culpa 💙"); flexible causes
  the matter-of-fact one. Zero LLM on the check path stands.
- **The guardian never rewrites; Reorganizar does.** missed_month announces the DERIVED new
  finish (frozen-plan doctrine); the formal rewrite is user-triggered only. `Goals::Replan` =
  re-activation semantics: initial_saved rebases to pre-current-month savings (actual saved
  provably invariant — the round-4 money trap), schedule re-anchors next month, commitment
  archived + recreated (paid history stays, parcels restart, source/payday carried), applied
  budget cuts revert now and re-arm for the new starts_on. Mid-month replan relieves sobra by
  exactly the unpaid parcel. Purchase goals only in v1 (savings_rate has no date to move).
- **Two honest options, live numbers.** estender (keep the exact parcel, finish later — the
  default) and manter a data (parcel rises; hidden when live capacity can't fund it), both from
  a FRESH Analyzer profile; draft-time user_caps are not carried. Modes cross the wire, numbers
  never do.
- **WA keyword = frozen regex.** "reorganizar" is a pre-pass like undo (the alert-advertised
  keyword must not depend on LLM mood); the whole chat is zero-LLM and supersedes an open
  goal-creation conversation instead of being swallowed as a slot answer.
