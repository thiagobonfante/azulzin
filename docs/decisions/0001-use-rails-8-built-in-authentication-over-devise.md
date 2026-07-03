# 1. Use Rails 8 built-in authentication generator over Devise

## Status

Proposed

## Context

azulzin is a greenfield Rails 8.1.3 app (schema v0, no models) needing email + password auth, email confirmation, password reset, and Google/Facebook social login. The two realistic foundations are Rails 8.1's built-in `bin/rails generate authentication` scaffold and the Devise gem. CLAUDE.md mandates simplicity-first, surgical changes, minimal surface.

Verified against railties 8.1.3: the generator produces ~150 lines we fully own — `User` (`has_secure_password`), `Session`, `Current` (ActiveSupport::CurrentAttributes), an `Authentication` concern (`require_authentication` / `allow_unauthenticated_access` / `start_new_session_for`), `SessionsController` + `PasswordsController`, a `PasswordsMailer`, `sessions/new` + `passwords/new` + `passwords/edit` views, and two migrations. Sessions are DB-backed with a signed, httponly, SameSite=Lax cookie. It is Turbo-native and matches the repo's stack (Propshaft, importmap, Hotwire, solid_*). Password reset comes free via `has_secure_password`'s `generates_token_for :password_reset`.

One verified caveat: the generator emits **no test files and no fixtures** (`hook_for :test_framework` has no matching authentication test generator), so we author our own minitest coverage.

Devise would give `registerable`, `recoverable`, and `confirmable` "for free" but layers Warden, orm_adapter, and responders on top, hides its controllers behind Warden, and needs extra config under Turbo. Crucially, OAuth is OmniAuth work either way — Devise's `omniauthable` is a thin wrapper over the same OmniAuth gems.

## Decision

Build on `bin/rails generate authentication`. Add a small hand-written `RegistrationsController`, an `EmailVerificationsController` + confirmation flow mirroring the generator's reset flow, and OAuth via OmniAuth. Author our own controller/integration/mailer/system tests (the generator ships none). Do not adopt Devise.

## Consequences

- We own and can read the entire auth surface; no Warden indirection.
- Registration (~20 lines) and email confirmation (~30 lines) are the only things hand-rolled that Devise would have given for free; both mirror patterns the generator already establishes (`generates_token_for`, `start_new_session_for`).
- We write the tests ourselves — a small, deliberate cost that also documents the intended behavior precisely.
- Fewer dependencies (bcrypt + OmniAuth gems) keeps the `bundler-audit`/`brakeman` surface small.
- Turbo behavior is explicit: registration success redirects `303 See Other`, validation failures `render ..., status: :unprocessable_entity` (422); the generator's own session/reset flows redirect on failure.
- We inherit the generator's hardening: rate limits on `sessions#create` and `passwords#create`, and `sessions.destroy_all` after a password reset.
- No `current_user` view helper by default (use `Current.user`); `has_secure_password` enforces no minimum length (we add one).

## Alternatives considered

- **Devise** — mature and feature-complete (`confirmable` especially), but its Warden machinery is larger than the entire rest of our auth surface, its Turbo story needs extra config, and it saves no OAuth work. Rejected as over-weight for a "super simple" app.
- **Hand-roll everything** — re-derives exactly what the generator produces (session cookies, token generation, rate limiting). Rejected as wasted effort and a larger bug surface.
