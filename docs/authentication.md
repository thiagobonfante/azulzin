# Authentication in azulzin

How accounts, sessions, and social login work once this feature is built. The foundation is Rails 8.1's built-in `bin/rails generate authentication` scaffold, extended with registration, email confirmation, and OmniAuth (Google + Facebook). We do **not** use Devise. The generator ships no tests or fixtures, so those are hand-authored.

## Models & schema

| Model | Table | Key columns | Notes |
|---|---|---|---|
| `User` | `users` | `email_address` (citext, unique, NOT NULL), `password_digest` (**nullable**), `confirmed_at`, `locale` (NOT NULL, default `pt-BR`) | `has_secure_password validations: false`; OAuth-only users have a NULL digest. `locale` is the UI/email language ([i18n](i18n.md)). No `name`/`avatar` columns (no consumer yet). |
| `Session` | `sessions` | `user_id` (FK), `ip_address`, `user_agent` | One row per active login. Session id lives in a signed cookie — no token column. |
| `OauthIdentity` | `oauth_identities` | `user_id` (FK), `provider`, `uid`, unique index `[provider, uid]` | One row per linked external account. No access/refresh tokens stored. |

`User` associations: `has_many :sessions` and `has_many :oauth_identities` (both `dependent: :destroy`). Email is normalized to `strip.downcase` and additionally case-insensitive at the DB via `citext`.

**Validations:** email presence/format/uniqueness always; `password` length ≥ 8 + confirmation **only when a password is set** (`allow_nil: true`); and `presence: true, on: :create`. The `on: :create` presence rule is the single source of truth for a blank sign-up password (it can't be a controller-only check because `password = ""` is a no-op the model reads back as nil). It passes for OAuth because that path supplies a random 32-char password, and it doesn't fire on updates (password reset).

**Helpers:** `user.verified?` (⇔ `confirmed_at.present?`) and `user.verify!` (sets `confirmed_at`).

## Session mechanism

- On login (`start_new_session_for(user)` from the `Authentication` concern) a `Session` row is created with the request's user agent + IP, and its id is stored in a **signed, permanent, httponly, SameSite=Lax** cookie named `session_id`. In production `config.force_ssl = true` adds the **Secure** flag.
- Every request: the global `require_authentication` before_action calls `resume_session`, loading the `Session` by signed cookie into `Current.session`; `Current.user` delegates to it. `Current` is `ActiveSupport::CurrentAttributes`, reset per request — always read `Current.user` / `Current.session`.
- Controllers are **secure by default**. Opt actions out with `allow_unauthenticated_access only: %i[...]` (literally `skip_before_action :require_authentication`).
- Sign-out (`terminate_session`) destroys the `Session` row and deletes the cookie. A password reset calls `@user.sessions.destroy_all`, logging the user out everywhere.

## Flows

**Sign up (email/password) — hard gate:** `GET /registration/new` → `POST /registration`. `RegistrationsController#create` builds the user and calls `@user.save` (model owns password presence via `on: :create`). On success it enqueues `UserMailer.email_verification` (`deliver_later`) and redirects to `/session/new` with `303` and a "check your email to confirm your account, then sign in" notice — it does **not** start a session. Invalid input re-renders `new` with `422` so Turbo shows inline errors.

**Email confirmation (doubles as first sign-in):** the mailer link is `email_verification_url(token: user.generate_token_for(:email_verification))` (24h expiry, keyed on the email so changing it invalidates the link). `GET /email_verification/:token` → `EmailVerificationsController#show` looks up the user via `find_by_token_for(:email_verification, token)`, calls `verify!`, then `start_new_session_for` and lands them on `/` signed in. An invalid/expired token redirects to sign-in with an alert. **Resend** is public and email-addressed (the user isn't logged in yet): `POST /email_verification` (`resend_email_verification_path`, rate-limited) takes an `email_address`, sends only if it maps to an unconfirmed user, and always shows the same enumeration-safe notice.

**Sign in — refuses unconfirmed accounts:** `GET /session/new` → `POST /session`. `SessionsController#create` uses `User.authenticate_by(...)`; on a match it checks `verified?` — if confirmed, `start_new_session_for` + redirect; if **not** confirmed, no session and a "please confirm your email first" alert pointing to the resend affordance. Wrong credentials give a generic "Try another email address or password." flash (no enumeration). Rate-limited 10/3 min.

**Sign out:** `DELETE /session` via `button_to` (Rails emits `303 See Other` for Turbo on non-GET redirects).

**Password reset:** `GET /passwords/new` → `POST /passwords` always shows the same generic notice (enumeration-safe) and, if the email exists, enqueues `PasswordsMailer.reset`. The token is provided free by `has_secure_password` (`password_reset_token`, **15-min** expiry, salt-bound so a changed password invalidates outstanding links — verified in activemodel 8.1.3, unaffected by `validations: false`). `GET /passwords/:token/edit` → `PATCH /passwords/:token` sets the new password and destroys all sessions. OAuth-only users can use this flow to set a first password.

**OAuth (Google / Facebook):** a `button_to "/auth/:provider"` POST (CSRF token attached, `data-turbo="false"`) hits the OmniAuth Rack middleware's request phase. The provider redirects back to `GET|POST /auth/:provider/callback` (route **constrained** to the two known providers) → `OmniauthCallbacksController#create`, which calls `User.from_omniauth(auth)`:
1. Nil auth → return nil (defense-in-depth; the route constraint already 404s unknown providers).
2. If an `OauthIdentity` with `(provider, uid)` exists → return its user.
3. Else, if the provider asserts a **verified** email (Google `extra.raw_info.email_verified`) and a matching `User` exists → link to it, **backfilling `confirmed_at`** if that account was still unverified.
4. Else create a new `User` (random password, `confirmed_at` set only if provider-verified) and its identity.

Creation runs in a transaction and rescues both `ActiveRecord::RecordInvalid` (an unverified match to an existing email → refused) and `ActiveRecord::RecordNotUnique` (identity race) → returns nil → the callback shows a friendly "add an email" alert. On success, `start_new_session_for(user)` gives OAuth logins the exact same `Session`/cookie as password logins. Facebook emails are never treated as verified, so Facebook never auto-links or auto-confirms. `/auth/failure` → back to sign-in with a generic alert. The callback uses `skip_forgery_protection only: :create` (OAuth `state` is the CSRF defense) and `allow_unauthenticated_access`.

**Native shells (Google + Apple):** the redirect flow above is impossible inside the iOS/Android webviews (Google 403s them). The shells use platform SDKs to obtain an **ID token** which the page POSTs to `POST /auth/:provider/token`; server-side verification funnels into the same `User.from_omniauth` (same `provider`/`uid`), so web and mobile resolve to the same account. Full mechanics, config surface, and pending items: [native-sso.md](native-sso.md).

## Routes table

| Verb | Path | Controller#action | Access |
|---|---|---|---|
| GET | `/registration/new` | `registrations#new` | public |
| POST | `/registration` | `registrations#create` | public · rate-limited |
| GET | `/session/new` | `sessions#new` | public |
| POST | `/session` | `sessions#create` | public · rate-limited |
| DELETE | `/session` | `sessions#destroy` | authed (303) |
| GET | `/passwords/new` | `passwords#new` | public |
| POST | `/passwords` | `passwords#create` | public · rate-limited |
| GET | `/passwords/:token/edit` | `passwords#edit` | public (token) |
| PATCH/PUT | `/passwords/:token` | `passwords#update` | public (token) |
| GET | `/email_verification/:token` | `email_verifications#show` | public (token) |
| POST | `/email_verification` | `email_verifications#create` | public · rate-limited (resend by email) |
| POST | `/auth/:provider` | *(OmniAuth middleware — request phase)* | public · CSRF via `button_to` |
| GET/POST | `/auth/:provider/callback` | `omniauth_callbacks#create` | public · provider-constrained |
| GET | `/auth/failure` | `omniauth_callbacks#failure` | public |

Route helpers: `new_registration_path`, `registration_path`, `new_session_path`, `session_path`, `new_password_path`, `edit_password_path(token)`, `email_verification_path(token)`, `resend_email_verification_path`.

## Config & credentials

**Setup runbooks (external services):** [Google OAuth](google-oauth-setup.md) · [Resend email + DNS](resend-email-setup.md) · [Facebook/Meta OAuth](facebook-oauth-setup.md) (deferred).

**`bin/rails credentials:edit`:**
```yaml
google:   { client_id: ..., client_secret: ... }
facebook: { app_id: "...", app_secret: ... }
resend:   { api_key: re_... }
```
`config/master.key` already exists and is git-ignored. **Production must receive `RAILS_MASTER_KEY`** (via Kamal: reference it in `.kamal/secrets` and `config/deploy.yml` `env.secret`) or it cannot decrypt any of the above.

**`config/initializers/omniauth.rb`** registers the two providers from credentials, keeps `OmniAuth.config.allowed_request_methods = [:post]` (default), and relies on `omniauth-rails_csrf_protection`. Never enable GET, `silence_get_warning`, or `provider_ignores_state`.

**Mailer From & language** — `app/mailers/application_mailer.rb` sets `default from: "no-reply@azulzin.com.br"` (replacing the generator's `from@example.com`; Resend rejects off-domain From) and an `around_action :set_locale` that renders each email in the recipient's `user.locale`. Mailers are therefore invoked parameterized — `UserMailer.with(user:).email_verification` / `PasswordsMailer.with(user:).reset` — and subjects come from locale files via `default_i18n_subject`. See [i18n.md](i18n.md).

**Mailer (production):** set `config.action_mailer.default_url_options = { host: "azulzin.com.br", protocol: "https" }` (replacing the `example.com` placeholder) and a single SMTP `smtp_settings` block (Resend: `smtp.resend.com:465`, user `resend`, password from `credentials.dig(:resend, :api_key)`). Enable `config.assume_ssl` and `config.force_ssl`. Development uses `letter_opener`; test uses `:test`.

**OAuth redirect URIs** to register: `http://localhost:3000/auth/{google_oauth2,facebook}/callback` (dev) and `https://azulzin.com.br/auth/{google_oauth2,facebook}/callback` (prod).

## Background email with Solid Queue

Mailers use `deliver_later`, which enqueues an Active Job. **The job only runs if a worker is running:**
- **Development:** Active Job's async adapter runs `deliver_later` in-process, and `letter_opener` pops the email in the browser. (Use `deliver_now` if anything looks stuck.)
- **Production:** `config.active_job.queue_adapter = :solid_queue`. Run the worker inside Puma (`SOLID_QUEUE_IN_PUMA=true`, already wired in `config/puma.rb`) — simplest for a single-server Kamal deploy — or as a dedicated `bin/jobs` accessory. With `raise_delivery_errors = true`, SMTP failures appear as **failed Solid Queue jobs**, so monitor the failed-jobs table.

## Tests (hand-authored — the generator ships none)

- `test/fixtures/users.yml` — a `confirmed` and an `unconfirmed` user (bcrypt digests at `MIN_COST`).
- `test/controllers/sessions_controller_test.rb` — sign-in success/failure, sign-out clears the cookie, and an **unconfirmed** user cannot sign in (hard gate).
- `test/controllers/registrations_controller_test.rb` — valid sign-up creates an UNCONFIRMED user with NO session + one enqueued email; blank password and duplicate email → 422.
- `test/integration/email_verification_test.rb` — valid token confirms **and signs in**; garbage token confirms nobody and starts no session; resend sends one mail for an unconfirmed address, zero for an unknown one (same reply).
- `test/mailers/user_mailer_test.rb` — guards that the From is `no-reply@azulzin.com.br`, not the `example.com` placeholder.
- `test/controllers/passwords_controller_test.rb` — known email enqueues one reset mail; unknown email enqueues zero with the same notice (enumeration-safe).
- `test/controllers/omniauth_callbacks_controller_test.rb` — verified Google creates a confirmed user/identity/session; verified Google links an existing password user and backfills `confirmed_at`; **unverified** Google never links to an existing account; Facebook creates a new unconfirmed user and never links. Uses `OmniAuth.config.test_mode` + seeding `Rails.application.env_config["omniauth.auth"]`.
- `test/system/authentication_test.rb` — full sign-up → gated at sign-in ("check your email") → confirm link both confirms and signs in (nav shows "Sign out").
