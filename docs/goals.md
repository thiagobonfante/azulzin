# Goals ("Metas") — how it works

Financial goals turn the ledger into forward motion: a household names a dream, azulzin computes
three concrete plans from its own numbers, and a weekly guardian watches the ledger and speaks up
only when behavior threatens the plan. Deterministic engine, AI only for phrasing. Decisions:
[ADR 0012](decisions/0012-goals.md) (engine/money/AI) + [ADR 0011](decisions/0011-proactive-notifications.md)
(the push posture). Design of record: `.plans/goals/`.

## The two kinds

- **purchase** — buy something worth `target_cents` by `target_date`. Required monthly =
  `⌈(target − initial_saved) / months⌉` (ceil, never undershoots).
- **savings_rate** — put away `target_cents` **in total** each month, open-ended. The form shows
  the household's current median guardado and asks for the new total (a total at or below today's
  guardado is refused at create); plans bridge only the extra.

At most **5 active goals per account** (bounds the weekly fan-out).

## The deterministic engine (`app/services/goals/`)

Every number is integer cents + BigDecimal — **no Float ever** (CI grep gate). Shared helpers +
value objects live in `app/services/goals.rb`.

- **`Analyzer`** — one grouped query over the trailing 3 full billing months + three `MonthSummary`
  reads → per-category **median** spend (never mean — one vet bill can't inflate a cap), the
  trimmable (commitment-less) slice, capacity base = `median(entradas − saidas − faturas)` (= sobra
  + guardado, so existing savers aren't understated), and a data-sufficiency verdict
  (`:ok`/`:thin`/`:insufficient`; >40% uncategorized → total-cap-only). Frozen verbatim into
  `goals.baseline`.
- **`PlanBuilder`** — 3 fixed personalities with cents-exact greedy trims, or — when
  `required > capacity + max trims` — three honest counter-offers (feasible date at capacity /
  feasible amount for the date / extra income needed). **Leve aims at 85% of the required effort**
  (`LEVE_EASE`; for savings the ease applies to the extra only), so it never collapses into
  recomendado when the sobra alone covers the goal — the projected date honestly slips instead.
  Capacity contention: a new goal's base subtracts other active goals' monthly targets. Pure
  function of the frozen baseline, so **choose recomputes byte-identically** and never trusts a
  params number.
- **User caps (orçamento sliders)** — on the draft Diagnóstico each flexible category gets a range
  slider (painted with the category color, bounded to its trimmable slice). Releasing a slider
  PATCHes `goals#caps` (stored in `goals.user_caps`, whitelisted + clamped server-side) and
  Turbo-swaps only the plan area. A cap is a **fixed cut carried in full by every plan** — it can
  flip an infeasible goal feasible (caps go past the 40% template max) and its money is committed
  even beyond the template's own target, so dragging accelerates all three plans. The chosen plan's
  cuts then flow to `TrimCaps` → `Budgets::Check` like any other cut. At the goal's `starts_on`
  (next month after activation) the cuts are also written into the standing category budgets by the
  daily `Goals::ApplyBudgetCutsJob` and reverted on abandon/achieve — dev has no recurring
  scheduler, so run `Goals::ApplyBudgetCutsJob.perform_now` from the console.
- **`Progress`** — actual (guardado since `starts_on`) vs pay-schedule-aware expected (0 before the
  household's earliest payday, then pro-rata). Pace is **always** guardado-vs-expected, never
  projected sobra (contributing early lowers sobra — flagging a saver for it is banned). Suppressed
  on a low-income month (< 70% of baseline income).
- **`Checker`** — the weekly status ladder (pace + large-purchase; achievement flips the goal).
  Category overspend lives in the extended `Budgets::Check`, not here.

## Pay yourself first

Activating a goal creates a `kind: "savings"` **Commitment** (`Goals::Activate`, guarded draft→active
transition + creation in one transaction). It behaves like rent: it shows in the commitments hub, it
reduces sobra *before* it's paid (`MonthSummary#projected_guardado_cents`), and paying it (through the
normal pay path, forked in `Commitments::MarkPaid`) posts a **transfer** into the caixinha — never an
expense. **Sobra is invariant at pay time**: the amount moves from `projected_guardado` to `guardado`.
Goals never move money themselves; the user pays the occurrence.

## The weekly guardian & alerts

`Goals::WeeklyCheckDispatchJob` (recurring.yml, Monday 11:00 UTC) fans out one
`Goals::NotifyMemberJob(account, member, as_of)` per membership of accounts with active goals — the
shipped dispatch→notify shape, in the mandatory shared `proactive_notify` concurrency group. Each
job writes an idempotent `goal_checks` row (unique `[goal_id, period_start]`) that the dashboard reads
for the pace chip. An alert-worthy check (worsened status or a new cause, past the 14-day cooldown)
records a `goal_alert`:

- **Dashboard** banner is free (via the shipped `notifications/_alert`).
- **WhatsApp** is opt-in per member (`notification_preferences.goal_alerts`), under the household
  master consent, capped at one goals message/user/week — all through `Notifications::Deliver`.
- **Celebration** (`goal_achieved`) is opt-OUT (default true) — celebrate loudly, correct quietly.

## AI (the only two touchpoints — `docs/decisions/0012`)

Both at creation, both async, both with template fallbacks. The controller analyzes the baseline
**in-request at create** — the narrative job fires milliseconds later on the async adapter and must
never race an empty snapshot (the job also skips un-analyzed drafts without burning quota):

- **`Narrator` + `NarrativeJob`** — one call phrases all 3 coach notes; a digit-mismatch guard
  rejects any invented money figure (template notes stand). ≤3 calls/session, ≤5 sessions/account/
  month (`goals.ai_calls_count`, increment-before-call).
- **`CategoryClassifier` + `ClassifyJob`** — one closed-set call labels custom categories, cached in
  `categories.flexibility` forever (exempt from the quota — structurally once-per-category).

Weekly checks and all WhatsApp copy are **zero-LLM** (a call-count test is the regression gate).

## i18n & tone

Every user-facing string is a key in both `pt-BR.yml` and `en.yml` (`goals.*`, `dashboard.goals.*`,
`activerecord.*`, `notifications.dashboard.goal_*`, `whatsapp.replies.notifications.goal_*`). Copy
follows the tone contract (`.plans/goals/02-ui-flow.md` §0): simple everyday language, honest
verdicts over encouragement, every hard truth paired with the number and one concrete way out.
Positive progress is azulzin **blue**, never green.
