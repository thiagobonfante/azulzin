# 2. OmniAuth for social login with (provider, uid) identities and verified-email-only linking

## Status

Proposed

## Context

We need Google and Facebook sign-in/sign-up on top of the Rails 8 `User`/`Session` model. The importmap-only stack has no Node/JS SDK, so both providers are plain server-side OAuth2 redirects via the OmniAuth Rack middleware. Two questions must be settled: which gems and how to configure them safely, and how to reconcile an external login with local accounts without an account-takeover hole.

OmniAuth's request phase was historically vulnerable to login CSRF (CVE-2015-9284). OmniAuth 2.x makes the request phase POST-only, but POST-only alone does not validate a Rails authenticity token; `omniauth-rails_csrf_protection` installs the request-validation phase that does. Older tutorials "fix" state/CSRF errors by re-enabling GET or setting `provider_ignores_state: true` — both reintroduce vulnerabilities.

For reconciliation, matching an OAuth login to a local account purely by email is the classic takeover vector: an attacker controlling a provider account bearing a victim's unverified email could absorb the victim's password account. Google reliably asserts `email_verified`; Facebook does not.

Two failure modes must not 500: (a) a request reaching the callback for an **unconfigured** provider leaves `request.env["omniauth.auth"]` nil; (b) a concurrent-login race on the `[provider, uid]` unique index raises `ActiveRecord::RecordNotUnique`.

## Decision

- Gems: `omniauth`, `omniauth-rails_csrf_protection` (mandatory), `omniauth-google-oauth2`, `omniauth-facebook`. Keep OmniAuth's default POST-only request phase and the CSRF request-validation phase. Never enable GET, `silence_get_warning`, or `provider_ignores_state`.
- Store external logins in `oauth_identities` keyed on a unique `(provider, uid)`. Look up by `(provider, uid)` first — email-independent.
- Auto-link a new identity to an existing password account **only** when the provider asserts the email is verified (Google `extra.raw_info.email_verified == true`); on such a link, backfill `confirmed_at` if the local account was still unverified. Facebook never auto-links or auto-confirms.
- Harden both non-500 paths: **constrain** the callback route to `provider: /google_oauth2|facebook/` (unknown provider → 404), **and** have `from_omniauth` `return nil` on a nil auth as defense-in-depth. Wrap creation in a transaction and rescue **both** `ActiveRecord::RecordInvalid` (duplicate-email refusal for an unverified match) and `ActiveRecord::RecordNotUnique` (identity race) → return nil → callback shows a friendly alert.
- Reuse `start_new_session_for(user)` for OAuth logins (one session system). Buttons are `button_to` POST forms (carry the CSRF token) with `data-turbo="false"` (next hop is a cross-origin redirect). The callback action uses `skip_forgery_protection only: :create` (OAuth `state` is the CSRF defense there) and `allow_unauthenticated_access`.

## Consequences

- No login-CSRF exposure; the OAuth state check stays on.
- Sign-in buttons must be POST forms — a plain GET link would (correctly) be rejected.
- OAuth-only users have a NULL `password_digest` (ADR 0005); they can set a password later via "forgot password".
- A verified Google login that matches an unconfirmed password account both links and confirms it (no lingering "confirm your email" banner).
- Neither an unconfigured provider nor a login race can 500 the callback.
- Facebook in production needs Meta App Review for `email`; until approved only Admin/Developer/Tester roles can log in. Facebook users start unverified and see the banner.
- We store no access/refresh tokens (sign-in only), keeping the identities table minimal.

## Alternatives considered

- **Match/link purely on email** — an account-takeover vector for unverified provider emails. Rejected.
- **Store provider/uid as columns on `users`** — blocks multiple linked providers and muddies the schema. A join table is barely more code. Rejected.
- **Rely only on the nil-guard (no route constraint)** — the guard alone prevents the 500, but the route constraint also stops junk `/auth/<garbage>/callback` traffic from ever reaching a controller. Kept both.
- **Devise `omniauthable`** — a thin wrapper pulling in Devise (ADR 0001). Rejected.
