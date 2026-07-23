# Goals ("Metas") — how it works

Financial goals turn the ledger into forward motion: a household names a dream, azulzin computes
three concrete plans from its own numbers, and a weekly guardian watches the ledger and speaks up
only when behavior threatens the plan. Deterministic engine, AI only for phrasing. Decisions:
[ADR 0012](decisions/0012-goals.md) (engine/money/AI) + [ADR 0011](decisions/0011-proactive-notifications.md)
(the push posture). Design of record: `.plans/goals/`.

## The two kinds

- **purchase** — buy something worth `target_cents` by `target_date`. Required monthly =
  `⌈(target − initial_saved) / months⌉` (ceil, never undershoots). The form asks whether the
  household is starting from zero or already has something saved ("Começar do zero" / "Já tenho
  um valor guardado") — a declared head start also records *which* caixinha holds it (see
  earmarking below).
- **savings_rate** — put away `target_cents` **in total** each month, open-ended. The form shows
  the household's current median guardado and asks for the new total (a total at or below today's
  guardado is refused at create); plans bridge only the extra.

At most **5 active goals per account** (bounds the weekly fan-out).

## Goals start next month

`starts_on` is always the **next month's** begin (`Goals::Recompute.start_month`) — for drafts
(the plans you're shown) and at activation alike: a plan for a month already half-spent would be
born broken. The savings commitment's first occurrence lands next month too. Through the gap
(activation) month: `Progress` expects **0** — but an eager transfer still counts, because
contributions anchor at `min(activation month, starts_on)` (`Progress#counting_from`; "guardado
continua guardado") — the show page says "começa em %{month}" instead of rendering a dead Pagar
button, and `Checker` grace runs to `max(activated_at + 14d, starts_on)` so the guardian never
flags the gap.

## The deterministic engine (`app/services/goals/`)

Every number is integer cents + BigDecimal — **no Float ever** (CI grep gate). Shared helpers +
value objects live in `app/services/goals.rb`.

**Display is whole reais.** Every goals figure renders through `MoneyHelper#brl_whole`: **ceil**
anything the user is asked to save or aim for (plan monthlies, targets, gap top-ups — never
undershoot the ask); **floor** the capacity/achievable/feasible family and real ledger figures
(actual saved, contribution history — never overstate what the household can do or holds; floor
also avoids the ceil→infeasible loop on counter-offer taps). Internal math and stored plan
snapshots stay **exact cents** (`Money.ceil_to_real`/`floor_to_real` round only at the edge;
< R$ 1 display divergence is accepted). Masked money inputs (`money_mask_controller.js`) are
digits-only whole reais — server prefills must be whole-real strings. Notification fork:
`goal_alert_*`/`goal_achieved` go whole-real on both channels; `budget_warn_goal`/
`budget_breach_goal` keep 2 decimals to match their sibling budget alerts. Non-goals surfaces
(account balances, the livre/guardado split) keep exact-cents `brl`.

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
  cuts then flow to `TrimCaps` → `Budgets::Check` like any other cut. Once `starts_on` arrives,
  the daily `Goals::ApplyBudgetCutsJob` (10:00 UTC in prod's recurring.yml) **writes the cuts into
  the standing `categories.monthly_budget_cents`** so the orçamento screen shows the cut values:
  min-tighten only (an already-tighter budget stands), budgets are *created* on unbudgeted
  categories, and every previous value is snapshotted into `goals.previous_budgets`. Abandon AND
  achieve revert immediately (`Goals::RevertBudgetCuts`) — manual edits win (a budget that no
  longer matches the written cap is left alone) and other active goals' caps are respected.
  `TrimCaps.for(account, month:)` is month-aware and remains the alert floor (effective limit =
  `min(budget, cap)`) even before the write-through lands. Dev has no recurring scheduler — run
  `Goals::ApplyBudgetCutsJob.perform_now` from the console.
- **`Progress`** — actual (initial saved + guardado since `counting_from`) vs pay-schedule-aware
  expected (0 through the pre-start gap and before the household's earliest payday, then pro-rata).
  Pace is **always** guardado-vs-expected, never projected sobra (contributing early lowers sobra —
  flagging a saver for it is banned). Suppressed on a low-income month (< 70% of baseline income).
  `projected_done_on` derives the honest forecast (current month + `⌈remaining / monthly⌉`,
  purchase only) — extra contributions pull it earlier with zero writes; the frozen plan stays
  "the original plan".
- **`Checker`** — the weekly status ladder (pace + large-purchase; achievement flips the goal).
  Category overspend lives in the extended `Budgets::Check`, not here.

## Pay yourself first — always linked, as parcels

Activating a goal creates a `kind: "savings"` **Commitment** (`Goals::Activate`, guarded draft→active
transition + creation in one transaction). It behaves like rent: it shows in the commitments hub
(the **"Guardar"** group, rendered first), it reduces sobra *before* it's paid
(`MonthSummary#projected_saved_cents`), and paying it (through the normal pay path, forked in
`Commitments::MarkPaid`) posts a **transfer** into the caixinha — never an expense. **Sobra is
invariant at pay time**: the amount moves from `projected_guardado` to `guardado`. Goals never move
money themselves; the user pays the occurrence.

- **Always linked.** Activation *requires* a caixinha (savings account) plus a **distinct** source
  account — the transfer needs both legs. Missing either (or source == caixinha) fails with
  `:missing_savings_account`; the choose step blocks with a create-caixinha CTA when the household has
  none. Both ids are whitelisted against the account (tenancy + savings-kind). Pre-round-3 goals
  may still be unlinked — `Progress` keeps the all-savings-accounts fallback for them.
- **Purchase goals are a parcelado.** `n = ⌈(target − initial_saved) / parcel⌉`, `ends_on =
  starts_on >> (n − 1)` — anchored on the *chosen* plan (leve honestly finishes later, acelerado
  earlier). The hub and the goal page show **N/total** (`Commitment#parcels_count` /
  `paid_parcels_count`); the goal show's parcel status line replaced the old "Guardar na caixinha"
  button (its Pagar link routes through the normal pay path; the gap month renders no button).
  **savings_rate** goals stay open-ended (fixo-like, `ends_on: nil`).
- **Standalone "Guardar".** The commitments hub can also create a savings commitment with *no*
  goal: it carries its own destination caixinha (`commitments.transfer_to_bank_account_id`,
  savings-kind, same account, ≠ source; a card can never be the source). `MarkPaid` destination =
  the goal's caixinha `||` the commitment's own — so hub pay, WA "paguei", and batch pay all work
  for standalone savings too.

## Earmarked money ("guardado para meta")

A purchase goal's declared head start records *where* it lives
(`goals.initial_saved_bank_account_id` — required when the amount > 0 and a caixinha exists; must
be a savings account of the same household; no hard balance validation at create). The bank
accounts page splits each caixinha's balance into **livre** and **guardado para meta**: per active
goal, initial saved + posted transfers into its caixinha since `Progress#counting_from`
(`GoalsHelper#goal_reserved_cents` mirrors that exact anchor so Σ reserved == Σ actual; clamped to
the balance; rendered exact-cents `brl` — balances are not goals figures).

## Speeding up

Purchase goals only: once this month's parcel is paid and the sobra is still ≥ 20% of it (integer
test `sobra × 5 ≥ parcel`), the show page offers an extra contribution (`Goals::SpeedUpOffer`).
`POST /goals/:id/contribute` re-derives the offer server-side (a render-time sobra is never
trusted), bounds the amount by the sobra, and posts a plain transfer into the caixinha — **no**
`commitment_id`, so the parcel history stays honest. The forecast responds because it's derived
(`Progress#projected_done_on`), not rewritten. The transfers save-money modal defaults its
destination to the active goal's caixinha, and the confirmation toast links back to the goal with
the new forecast (savings_rate goals get "conta pra meta" framing instead of a date).

## Creating a goal over WhatsApp

"Quero juntar 20 mil pra uma viagem" starts the flow: the **one** shared-Extractor call that
classified `create_goal` also seeds the slots (kind / name / amount / month phrase / initial saved
— raw words only; Ruby does all parsing via `Money.to_cents` + `Whatsapp::GoalMonthPhrase`).
**Every reply after the trigger is deterministic — zero LLM.** State lives in `goal_conversations`
(one open per sender, 24h TTL refreshed on every ask, lazily expired):
`collecting → offered → picking_caixinha → picking_source → closed`, transitions via the
guarded-update idiom (a double "sim" matches zero rows).

- **collecting** — asks the missing slots in order (purchase: name → amount → month → initial
  saved; savings_rate: just the monthly total).
- **offered** — the real draft Goal is created (Analyzer baseline computed in-job *before* save —
  the same race fix as the web controller) and a **single recomendado plan** is presented: a
  deliberate deviation from the web's 3 personalities (chat can't compare 3 cards; the app remains
  the place to explore). An infeasible goal presents the honest counter-offer, auto-applied on
  "sim".
- **picking_caixinha / picking_source** — accept is **always-linked**: no caixinha or no distinct
  source → friendly "crie uma caixinha no app" block and the draft is destroyed; exactly one →
  auto-picked; two or more → numbered pick (options stored in *prompt order*, reloaded with
  `in_order_of`). Activation reuses `Goals::Activate`, so the goal starts next month like any
  other.

Boundaries: an open *transaction* ask always wins — the goal router hooks in **after** the txn
open-ask check, so a numeric reply to "qual conta?" is never eaten by the goal chat. Receipts and
images bypass the goal hook entirely (nil text falls through to the receipt pipeline — a receipt
sent mid-chat still posts). WA drafts consume the ≤5 monthly AI sessions but never fire
`NarrativeJob` (there are no coach notes to phrase in chat). Cancel ("cancelar"/"deixa"), reject
("não") and TTL expiry **destroy the draft** — an invisible draft would leak the quota. See
`Whatsapp::GoalFlowHandler`/`GoalFlowRouter`; replies live under `whatsapp.replies.goal_flow.*`
(💙, never 🎉).

## The weekly guardian & alerts

`Goals::WeeklyCheckDispatchJob` (recurring.yml, Monday 11:00 UTC) fans out one
`Goals::NotifyMemberJob(account, member, as_of)` per membership of accounts with active goals — the
shipped dispatch→notify shape, in the mandatory shared `proactive_notify` concurrency group. Each
job merges the per-goal `Goals::Checker` result (pace + large-purchase) with the account-level
`Goals::RiskScan` (round 4, below), writes an idempotent `goal_checks` row (unique
`[goal_id, period_start]`) that the dashboard reads for the pace chip, and — on an alert-worthy
moment — records a `goal_alert` whose payload is the worst NEW cause (priority: missed_month >
red_month > next_month_red > budget_raised > pace > big_purchase):

- **Dashboard** banner is free (via the shipped `notifications/_alert`), now with a "Ver meta"
  deep-link to the goal page's `#replan` section.
- **WhatsApp** is opt-in per member (`notification_preferences.goal_alerts`), under the household
  master consent, capped at one goals message/user/week — all through `Notifications::Deliver`.
- **Celebration** (`goal_achieved`) is opt-OUT (default true) — celebrate loudly, correct quietly.

## The predictive arm (`Goals::RiskScan`) — warn BEFORE it breaks

Zero-LLM findings computed once per sweep over the live ledger (round 4):

- **`red_month`** — the current month's projection (`MonthSummary#remaining_cents`, which
  already nets unpaid parcels via `projected_guardado`) closes negative while goal parcels sit
  in it. Fired once per account, attached to the goal with the largest parcel — never one
  banner per goal. Silent when no goal money is in the month (that's the budget/summary kinds'
  story, not a goals alert).
- **`next_month_red`** — the same test on NEXT month, whose faturas already carry posted card
  spend billing forward ("comprei no cartão, cai no mês que vem") plus card commitments and
  expected incomes — the goal that won't fit is flagged weeks ahead.
- **`budget_raised`** — after `ApplyBudgetCuts` wrote a goal's caps into the standing budgets,
  a member raised one above the cap (manual edits win, and `TrimCaps` keeps pinning the spend
  alerts — this warns that the *intent* breaks the goal's math). Names the worst offender.
- **`missed_month`** — last month's contributions into the caixinha came in under the parcel.
  The payload carries the **derived** new finish (`Progress#projected_done_on` — the frozen
  plan is never auto-edited) and a deterministic cause: lower income first (< 70% of the
  baseline median), else the worst category overage vs the frozen baseline medians (≥ R$ 50).
  An essential-category or income cause selects the **gentle** copy variant ("imprevistos
  acontecem, sem culpa 💙"); flexible causes get the matter-of-fact one. Fires only when the
  finish actually slips past the chosen plan's promise.

Risk findings escalate the check status (any ⇒ at least `at_risk`; missed/red ⇒ `off_track`),
bypass the activation grace and — being predictive protection — the 14-day cooldown
(`budget_raised` keeps it). A goal **replanned in the last fortnight sits out the red
projections** — the household just reorganized; the switch stays quiet. The delta-gate is
keyed on `(finding, category, month)` and compares against the causes behind the member's
**last alert** (not last week's silent check), so each concrete cause alerts exactly once —
and a cause the cooldown suppresses still fires when the cooldown lifts. The weekly WA guard
and daily cap always stand. Every risk template ends with the way out:
**responda *reorganizar***.

## Reorganizar — replanning without guilt

The ONLY path that rewrites an active goal's plan, always user-triggered. `Goals::ReplanOffer`
quotes two options from a FRESH `Analyzer` profile (never the frozen baseline — reality moved,
that's the point), purchase goals only:

- **estender** (default): keep the exact parcel, finish later — new `target_date` =
  next month + ⌈remaining/parcel⌉ (the founder's "jan/2027 → fev/2027").
- **manter a data**: keep the date, the parcel rises to ⌈remaining/months-left⌉ — hidden when
  live capacity can't fund it or it wouldn't beat estender.

`Goals::Replan` applies as a **re-activation** in one transaction: `initial_saved` rebases to
everything saved through last month (current-month transfers keep counting through the fresh
window — `Progress#actual_cents` is provably invariant, the round-4 money trap), the earmark
re-anchors on the goal's caixinha, `activated_at`/`starts_on` reset (grace + gap month restart,
so the guardian is quiet through the switch), the old savings commitment is archived with its
paid history (parcels restart 0/n on a fresh commitment carrying the same source account and
payday), and applied budget cuts revert immediately — the daily job re-applies the new plan's
cuts when the new `starts_on` arrives. Replanning mid-month archives the unpaid occurrence, so
the sobra gets relief by exactly the old parcel, now.

Surfaces: the goal page's collapsible **Reorganizar** section (`#replan`, open when the latest
check is at_risk/off_track; radio options → `PATCH /goals/:id/replan`, mode-only params —
numbers are re-derived server-side), and the WhatsApp keyword **reorganizar** (frozen-regex
pre-pass, zero LLM end to end): one candidate goal goes straight to the numbered offer, several
get a pick, "sim"/"1"/"2" applies, "não" keeps, and the keyword supersedes an open
goal-creation chat instead of being swallowed as a slot answer.

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
