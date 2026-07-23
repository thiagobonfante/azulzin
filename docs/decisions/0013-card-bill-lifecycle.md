# 13. Card bill lifecycle: derived truth, conferência, parcelamento

## Status

Accepted (2026-07-22)

## Context

Credit-card faturas are where captured spending meets the bank's own arithmetic. A closed bill
must show a figure, take a payment, survive a divergent bank statement, carry an unpaid remainder
forward (rotativo) and accept a bank-contracted parcelamento — all while every one of those moves
stays reversible, because the ledger's house rule is that deleting/undoing a row IS the rollback.
The design question was what to store versus derive, and whose number rules when ours and the
bank's disagree. Decisions were settled across the 6-phase build and two founder review rounds
(2026-07-22); this ADR records the contracts. Detail lives in `.plans/credit-cards/`.

## Decision

**A `CardBill` stores snapshots and annotations; everything a user acts on is derived live.**
The row is materialized on close (`CardBills::CloseScan`) and holds only close-time facts
(`billing_month`, `closed_on`, `due_on` — settled history a config edit never rewrites) plus the
bank's numbers as the user informs them (`stated_total_cents`, `stated_minimum_cents`) and the
conferência journal (`review_log`). Totals, paid, and status are computed on read, so a
late-arriving capture or an unpay can never contradict a stored copy.

**Status is derived, and refined so a settled bill never screams "vencida".** Base status
(unpaid / partially_paid / paid) comes from payment transfers linked via `card_bill_id`.
`display_status` refines it: **paid_late** ("paga em atraso") when fully paid but the last
payment landed after `due_on`; **rolled** ("restante na fatura seguinte") when the unpaid
remainder was absorbed by a newer closed bill via carryover — the debt lives there now, so the
old bill loses its Pagar entry and the cards-page badge probes only the NEWEST bill (one debt,
announced once); **financed** ("parcelada") when a parcelamento exists. **A financed bill counts
as paid everywhere** (`paid?` = financed? || fully paid): Pagar CTA, rotativo warning and
card_due/card_overdue banners all key off the one `paid?` guard — only the status tag reads
"parcelada". Dashboard bill alerts are likewise derived at render, never dismissed on pay:
payment is a reversible transfer, and undo must bring the banner back.

**Our figure rules until a conferência resolves.** `our_total_cents` = posted rows +
`Carryover.estimate` — the comparison baseline everywhere, because transaction rows can never
contain encargos, so raw computed vs the bank's number is nonsense on a rotativo bill.
`effective_total_cents` — THE figure every surface shows (headline, badge, bills history, Pagar
prefill, rotativo math, reminders) — is the bank's stated total only once the conferência
RESOLVES; while pending (stated ≠ ours) and when no stated exists, it falls back to
`our_total_cents`. Informing a diverging value changes NOTHING except a warning and a disabled
Pagar: the user keeps seeing our total until the focused review (move closing-edge rows, add
missed purchases, register a ± adjustment) concludes or is cancelled. The carryover/encargos
lines are the figure's PERMANENT breakdown — never suppressed, even after a stated is accepted
(resolving equalizes our figure with the bank's, so the lines keep summing to the total);
`MonthSummary` adds the carryover term only for OPEN months (a closed bill's effective already
contains it).

**The conferência is fully reversible via a journal, not stored state.** `card_bills.review_log`
(jsonb) records what the review did: `carry_over` entries log moved rows with their prior
`billing_month_manual`, `adjust` entries log the adjustment row's id. "Cancelar conferência"
replays the log BACKWARDS — moves return, adjustment rows soft-delete — then forgets stated.
Informing a value starts a fresh log, so an older settled conference can't be unwound later.
Added missing purchases deliberately SURVIVE cancel: they are real spending the user found, not
review bookkeeping. Adjustment rows are ordinary deletable ledger rows (deleting one is its own
rollback) and count in month metrics as normal income/expense (the Mobills/Organizze posture;
founder may revisit).

**Parcelamento de fatura is a financing record plus derived parcel lines — never transaction
rows.** `card_bill_financings` stores the BANK's numbers verbatim (`installments_count`,
`installment_cents`, `financed_cents`, `first_charge_month` = bill month + 1) — parcela and
count come from the bank's app, never computed; a Commitment was rejected because its principal
would double-count captured spending. Parcels ride the Carryover spine: ONE composition point,
`CreditCard#bill_cents` += `financing_parcels_cents(month)`, so closed bills, the hub tile and
MonthSummary inherit them automatically; `Carryover.estimate` returns nil when the previous bill
is financed (the contract replaces the rotativo). Encargos (parcela × count − financed) are
recognized per parcel, split evenly with the remainder on parcel 1. **Limit hold/release mirrors
the banks:** `used_cents` += `held_cents` — the financed principal keeps consuming limit,
released proportionally as parcel months are billed; the card is NOT blocked (CMN 4.549 /
Lei 14.690). The optional entrada rides the financing form as a normal Pay transfer posted in
the same transaction, journaled via the `down_payment_transaction` FK. **Destroying the financing is
the whole rollback:** parcels and limit hold vanish (they were derived), plain carryover returns
on its own, and the form's entrada is `reverse!`d in the destroy transaction — a payment
recorded via Pagar beforehand is not the form's and survives cancel.

## Consequences

- No stored status or total can go stale: unpay, undo, late captures and cancel all resolve by
  re-derivation, not by compensating writes.
- Reversibility has two idioms, used deliberately: derived state rolls back by deleting its
  source record (financing, adjustment row), imperative review actions roll back by replaying
  the `review_log` journal.
- Financings and conferências created BEFORE their journal migrations (entrada FK
  20260723060001, review_log 20260723011206) have an empty link/log — their rollback is manual
  (undo the payment via Pagamentos / delete the "Ajuste da fatura" row).
- Reconciliation PDF runs will flag the bank's parcel line as missing-in-app (parcels are
  derived, not rows) — reviewable, the user unchecks; a known gap.
- WA intents ("paguei a fatura", "parcelei a fatura") stay phase-7; contracts here are the
  seam they will ride.
- Pins live in `test/e2e/web/card_*` (BILL-01..05, ROT-01..02, REC-01/05, SUB-01) — the
  status-refinement, pending-figure, rollback and financing money paths are all golden-tested
  in exact centavos.
