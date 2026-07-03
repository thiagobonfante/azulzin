# 4. Email verification uses a hard gate

## Status

Accepted (2026-07-03)

## Context

Email/password sign-ups need email confirmation. The gating policy is a UX/security tradeoff:

- **Hard gate** — no session on sign-up; the verification link both verifies and signs the user in. A password sign-in is refused until the email is confirmed. Least app machinery (no persistent "unverified" state walking around the app), stricter, but a dead-end if the email is slow or lost — mitigated by a resend path.
- **Soft gate** — sign the user in immediately, mark them unverified, nudge them to confirm with a banner.

azulzin is a personal-finance app: a trustworthy email on file matters, and we prefer that an account cannot transact from an unconfirmed address. OAuth users authenticated by a provider-verified email (Google) are created already-confirmed, so they never hit the gate.

## Decision

Adopt a **hard gate** for password accounts:

- **Sign-up** creates the user `confirmed_at: nil` and does **not** start a session. It enqueues the verification email and redirects to the sign-in page with a "check your email to confirm your account" notice.
- The confirmation token is `generates_token_for :email_verification, expires_in: 24.hours` keyed on `email_address` (changing the email invalidates a pending link). Clicking the link sets `confirmed_at` **and signs the user in** (`start_new_session_for`), landing them in the app — the confirmation click is the account's first login.
- **Password sign-in refuses an unconfirmed account**: `SessionsController#create`, after `authenticate_by`, checks `verified?`; if false it does not start a session and redirects back with an alert plus a pointer to resend.
- **Resend is a public, email-addressed, rate-limited, enumeration-safe endpoint** (the user is not signed in, so it cannot rely on `Current.user`): it always shows the same "if that address needs confirming, we've sent a link" notice and only sends when the address maps to an unconfirmed user.
- **OAuth is a separate provider-authenticated path** and is not subject to the password gate: Google logins (provider-verified email) are created/linked `confirmed_at`-set and signed in. Facebook logins (deferred, see ADR 0002) are provider-authenticated but their email is unverified — when Facebook ships they are signed in by OAuth yet left `confirmed_at: nil`, which the future money-controller guard will treat as unverified.
- We still do **not** add a `require_email_verification` `before_action` now — there are no money/data controllers to protect, so it would be dead code (CLAUDE.md "no speculative code"). The hard gate lives entirely in the sign-in/sign-up path today; the enforcement guard is a one-line future addition when protected controllers arrive.

## Consequences

- An unconfirmed account cannot obtain a session via password login — no unverified users roam the app, so there is no "unverified" banner to maintain.
- The only recovery path for a lost email is the public resend endpoint; it is rate-limited and enumeration-safe.
- A confirmation click doubles as the first sign-in, so the happy path is: sign up → check email → click → you're in.
- Because unverified emails never yield a session on the password path, we remain consistent with ADR 0002 (never treat an unverified email as proof of ownership for OAuth linking).
- Slight friction versus a soft gate: a user who mistypes their email or loses the message is blocked until they resend/correct it. Accepted for a finance app.

## Alternatives considered

- **Soft gate** (the originally recommended default) — sign in immediately with an "unverified" banner + resend. Calmer first impression, but lets an unconfirmed address use the app and adds always-on banner machinery. Rejected in favor of a trustworthy-email-first posture for finance.
- **Hard gate WITH a pre-wired `require_email_verification` guard** — carries a `before_action` wired to no controller: dead code today. Dropped; we add it only when a protected controller exists.
- **No verification at all** — unacceptable for a finance app that needs a trustworthy email on file.
