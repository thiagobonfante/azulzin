# 10. Auto-categorization: merchant memory first, closed-set LLM second

## Status

Accepted (2026-07-07)

## Context

Categorizing was manual everywhere except one narrow path: the WhatsApp text pipeline resolved
the LLM's free-text category guess by trigram similarity (≥ 0.75) against the account's
categories — duplicated across two deciders, absent from the receipt/photo path, and the
document-import classifier's `category_guess` was generated then discarded. Manual quick-add had
no inference at all, and nothing anywhere remembered that the user always files "ifood" under
Restaurantes. Uncategorized spend accumulated as a first-class "Sem categoria" bucket.
Full plan: `.plans/auto-categories/` (gitignored, 5 docs).

## Decision

One shared engine with a strict two-step ladder, wired into every capture surface:

- **Merchant memory first (D1):** `Categories::Suggest` — the modal category of the account's
  last 20 *human*-categorized rows for the same normalized merchant (`merchant_norm` column,
  indexed), firing at ≥ 60% share. Deterministic, LLM-free, per-account (a household shares its
  taxonomy).
- **LLM label second (D2):** `Categories::Resolve` centralizes the ≥ 0.75 trigram match
  (`MATCH_MIN`), with an exact-normalized-name fast path. The LLM only ever emits a **label
  string** — never an id, never money. Prompts inject the account's kept category names
  (closed-set, ≤ 30, usage-ordered, in the user message) so the model answers inside the user's
  own taxonomy; resolution stays in Ruby regardless.
- **Provenance (D3):** `transactions.category_source` ∈ `user | memory | ai | NULL`(legacy).
  **Memory learns only from `"user"` rows** — machine-assigned categories never feed the memory,
  so model mistakes cannot self-reinforce. A manual category edit flips any row to `"user"`.
- **Surfaces (D4):** WhatsApp text + receipt + installment paths assign silently (existing
  posture) and the reply names the category (cheap correction loop); a "muda pra X" chat intent
  corrects the last row. Quick-add gets a *preselect-only* suggestion (no silent server-side
  assignment; no LLM in the synchronous path). Import proposals carry the resolved
  `category_guess` for review. A capped backfill job (memory pass free, then batched closed-set
  calls) categorizes history silently, with everything editable in the ledger.
- **Scope guards (D5):** category stays optional at every layer; transfers and incomes stay
  categoryless; no rules table, no embeddings, no new LLM call outside existing pipelines.

## Consequences

- Repeat merchants — most real spend — categorize deterministically at zero marginal cost; AI
  spend is unchanged (closed-set lines piggyback on calls that already happen).
- `TextMatch` now owns the normalize/similarity primitives (`Whatsapp.*` delegates preserved).
- The `"user"`-only learning rule means memory quality grows with corrections; legacy NULL-source
  rows stay inert until touched, which is slower to warm up but never poisoned.
- A wrong silent category on WhatsApp is visible in the reply and one edit away — accepted
  trade-off for keeping the zero-friction capture posture.
