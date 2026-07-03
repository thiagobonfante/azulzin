# 5. Accounts data model: nullable password_digest, citext email, oauth_identities, no profile columns

## Status

Proposed

## Context

The Rails 8 generator's `CreateUsers` migration (`email_address:string!:uniq password_digest:string!`, verified) makes `password_digest` NOT NULL. That conflicts with OAuth-only users, who legitimately have no password. We also need reliable case-insensitive email uniqueness (account-linking depends on it) and a place to record verification state and external identities.

Verified in activemodel 8.1.3: `has_secure_password` default validations add `errors.add(:password, :blank) unless password_digest.present?` on every save; `authenticate`/`password_salt`/the `password=` and `password_confirmation=` accessors are defined in `InstanceMethodsOnActivation`, which is included **regardless** of the `validations:` flag; `reset_token: true` is the default **independent** of `validations:`, so `generates_token_for :password_reset` and `find_by_password_reset_token!` remain available with `validations: false`; and the `password=` setter drops an empty string to nil (`password = ""` is a no-op).

Because `password = ""` is a no-op, an `allow_nil` length validation cannot enforce *presence* for a blank sign-up password — presence must be asserted separately.

## Decision

- `users`: `email_address` as `citext NOT NULL` + unique index (case-insensitive uniqueness at the DB, defense-in-depth alongside `normalizes` strip+downcase); `password_digest` **nullable**; `confirmed_at:datetime` (NULL = unverified). Use `has_secure_password validations: false` and re-add explicit `validates :password, length: { minimum: 8 }, confirmation: true, allow_nil: true` plus email presence/format/uniqueness.
- Enforce password **presence** with `validates :password, presence: true, on: :create` on the model. This is correct for **all** creators: email sign-up must supply one, and the OAuth path supplies a random 32-char password, so it passes; updates (password reset) are unaffected by `on: :create`. This replaces the earlier controller-side `valid?` + manual `errors.add` dance (which validated twice).
- **No `name` / `avatar_url` columns.** No in-scope UI consumes them; adding them now is speculative (CLAUDE.md). When a profile screen lands, a migration + a couple of `from_omniauth` assignments add them.
- `sessions`: exactly as generated (user FK, ip_address, user_agent). Session id lives in a signed httponly cookie — no token column.
- `oauth_identities`: `user_id` (FK, NOT NULL), `provider` (NOT NULL), `uid` (NOT NULL), unique index on `[provider, uid]`. No access/refresh token columns (sign-in only).
- Tokens carry no columns: password-reset comes free from `has_secure_password`; email-verification uses `generates_token_for :email_verification` with state in `confirmed_at`.

## Consequences

- OAuth-only users save cleanly with a NULL digest; they can later set a password via "forgot password".
- The model is the single source of truth for password presence; the `RegistrationsController` is a plain `if @user.save`.
- `citext` requires `enable_extension "citext"` — standard on PostgreSQL; the migration enables it guarded.
- Losing the built-in validations means we own length/confirmation/presence checks (added explicitly) — a small, documented deviation from the generator.
- `email_verification` is keyed on `email_address`, so editing the email before confirming invalidates the outstanding link (the Resend path covers this).
- The unique `[provider, uid]` and unique `email_address` indexes encode the linking rules structurally.

## Alternatives considered

- **Controller-side presence dance** (`@user.valid?` then manual `errors.add(:password, :blank)` then `errors.empty? && save`) — runs validations twice and splits the rule across model and controller. Replaced by `on: :create` presence, which is cleaner and works for OAuth because it supplies a password. Chosen.
- **Conditional model validation** (`validate { ... if new_record? && password_digest.blank? && oauth_identities.empty? }`) — couples the model to record-creation order and is fiddlier than `on: :create`. Rejected.
- **Keep `password_digest` NOT NULL, give OAuth users a random password** — a lie in the data model; blocks a clean "has this user set a password?" check. Rejected.
- **Keep `name`/`avatar_url`** — nice-to-have but unused; against simplicity. Deferred to when a profile UI exists.
- **Plain `string` email + `normalizes` only** — relies solely on app-level downcasing; `citext` adds DB-level safety for one line. Chosen `citext` (plain string is an acceptable fallback if the extension is unavailable).
