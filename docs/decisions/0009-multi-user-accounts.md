# 9. Multi-user accounts: an Account tenant for family households

## Status

Accepted (2026-07-06)

(The plan referenced this ADR as "0007-multi-user-accounts"; 0007 was already taken by the
host-based marketing/app split, so it lands as 0009.)

## Context

azulzin shipped single-user: the tenancy unit was `users.id`, every domain table carried
`user_id NOT NULL`, and every controller scoped through `Current.user.<assoc>`. The product
need ("adicione sua esposa") is a shared household: up to four family members operate one pool
of financial data — bank accounts, cards, transactions, commitments, incomes, categories,
document imports, WhatsApp movements — each with their own login and their own WhatsApp phone,
while every row remembers who created and last changed it, and nothing is hard-deleted in normal
use. It builds on ADR 0005 (accounts data model), 0004 (email-verification gate), 0002 (OmniAuth
linking), and 0006 (i18n). Full plan: `.plans/multi-user/` (gitignored, 9 docs).

## Decision

Introduce an **`Account`** model as the tenant and re-root scoping onto `Current.account`.

- **Tenant (D1):** `accounts` + `account_memberships` (roles `owner|member` only). One account
  per user, ever (unique `user_id`); exactly one owner (partial unique `WHERE role='owner'`);
  hard cap of 4 via a `members_count` counter cache + a Postgres `CHECK (members_count BETWEEN
  0 AND 4)` + a locked app validation. No billing, no RBAC beyond owner/member, no multi-account
  membership, no data partitioning inside a family.
- **Scoping (D2):** denormalized `account_id NOT NULL` on the 7 domain tables; each old `user_id`
  is **renamed to `created_by_id`** (attribution, never scoping; `ON DELETE SET NULL`).
  `whatsapp_messages.account_id` is nullable; its `user_id` keeps its name ("resolved sender").
  `Current.account` via `delegate :account, to: :user`. Explicit association scoping stays the
  law — no `default_scope`, no acts_as_tenant.
- **Migration (D3):** one deploy, four sequential migrations (create tables → add nullable
  columns + rename + FK re-point → in-migration backfill of one account per user → NOT NULL +
  index swaps). `pg_dump` before deploy is the rollback of record; rehearse on a prod dump.
- **Invitations (D4):** `invitations` row, plaintext `SecureRandom.base58(32)` token, 7-day
  expiry, owner-only. Acceptance is **token possession, not email equality** (survives Google
  with a different email); a signed-in visitor must **confirm via POST** — a GET never changes
  state (a state-changing GET that can destroy the visitor's fresh account is a CSRF/tenant-
  capture hole; SameSite=Lax does not cover top-level GET navigations). The session token
  carries a 30-minute TTL.
- **Onboarding (D5):** `onboarded_at` stays per-user; step guards count **account** data so an
  invited member auto-passes stocked steps; an explicit "skip to the app" affordance appears once
  the account has instruments. Category seeding is account-scoped and idempotent (first seeder's
  locale wins).
- **WhatsApp (D6):** phone identity stays on `users` (one phone = one user). Resolution is
  JID → user → **user.account**; every AI-committed row is stamped `account` + `created_by:
  sender`. Conversation state (open ask, undo referent, reply routing, job serialization) stays
  per phone.
- **Attribution (D7) & soft delete (D8):** hand-rolled `Attributable` (`created_by`/`updated_by`,
  stamped from `Current.user` in requests and **explicitly** in jobs) and `SoftDeletable`
  (`deleted_at`, explicit `.kept`, no `default_scope`). Soft delete cascades to nothing; the LGPD
  hard-destroy chain **moves from User to Account**. Attribution renders only when the account has
  >1 member.
- **Authorization (D9):** one concern, `AccountOwnership#require_owner!` (explicit boolean
  contract), gating invite/revoke, member removal, ownership transfer, account rename/delete.
  Account deletion terminates **every** member's sessions in-transaction.
- **Naming (D10):** models `Account`/`AccountMembership`/`Invitation`; concerns `AccountScoped`/
  `Attributable`/`SoftDeletable`; `Current.account`; columns `account_id`/`created_by_id`/
  `updated_by_id`/`deleted_at`/`deleted_by_id`.

### Accepted deviations from the plan's recommendations

- **Phone stays required to finish onboarding** (open decision #13): the plan recommended
  relaxing `skippable?` to name-only for invited members, since phone only feeds WhatsApp
  verification. The owner chose to keep phone required — an explicit, accepted deviation from
  requirement R4's "fully skippable"; a member who never wants WhatsApp still enters a number.
- **The owner names the household during onboarding** (open decision #1): rather than
  settings-rename only, the profile step shows an owner-only "shared account name" field
  (invited members never see it). The settings-page rename card remains.

## Consequences

- Migration B's `user_id → created_by_id` rename is a one-way door: the previous app image
  cannot run on the migrated schema. Deploys pause the WhatsApp sidecar during the window;
  `HandlerHelpers#account` back-stamps any nil-account message so nothing is lost.
- `.kept` must be opted into on every read path (no default_scope). It is folded into
  `Transaction`'s composed scopes as the aggregate choke point; other reads add it explicitly.
  The `source_message_id` unique indexes deliberately do **not** gain a `deleted_at` condition,
  so a redelivered WhatsApp webhook can never resurrect a soft-deleted row.
- Attribution is invisible until the first invite lands (every account is solo at migration),
  so it must be fully baked beforehand.
- Restore is console-only in v1 (no trash UI, no purge job).
- A guessed `AZUL-XXXX` code now binds into a family tenant, so unknown-sender code attempts are
  capped per JID per day and a double phone-bind replies `phone_already_linked` instead of
  failing silently.

## Alternatives considered

- **`acts_as_tenant` / `default_scope`** — implicit scoping hides the tenant boundary and fights
  the app's existing explicit-association ethos; a forgotten `unscoped` becomes a data leak.
  Rejected in favor of explicit `Current.account.<assoc>`.
- **A `discard`-style gem for soft delete** — trivial to hand-roll, and its default-scope
  temptation is exactly what we reject. Rejected.
- **Auto-accept an invite on GET for signed-in users** — a state-changing GET that can destroy
  the visitor's account and re-tenant them. Rejected for an explicit confirm POST (security, not
  preference).
- **Per-account WhatsApp numbers** — one commercial number, one sidecar; identity stays on the
  user. A phone bound to an account would still need per-sender identity for attribution.
  Rejected.
- **Expand/contract multi-deploy migration choreography** — enterprise theater at 3 users of
  data; one deploy with a pg_dump rollback is honest. Rejected.
