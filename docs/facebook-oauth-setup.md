# Facebook (Meta) OAuth setup — Phase 5, deferred

> **Status: deferred.** Per the "Google first" rollout decision, the Facebook *code* is not
> built yet (no `omniauth-facebook` provider in `config/initializers/omniauth.rb`, and the
> callback route is constrained to `google_oauth2` only). This runbook prepares the Meta
> console side so it's ready when Phase 5 lands. See [ADR 0002](decisions/0002-omniauth-social-login-and-account-linking.md)
> and the plan's Phase 5.

## Why it's deferred

Meta requires **App Review** before real users can grant the `email` permission. Until the app
is approved, only accounts with an **Admin / Developer / Tester** role on the Meta app can log
in. Google's email/profile scopes are non-sensitive (no review), so Google ships first.

## 1. Create the Meta app (developers.facebook.com)

- <https://developers.facebook.com> → **My Apps → Create App** → type **Consumer**. The app
  starts in **Development** mode.
- Add the **Facebook Login** product.
- **Settings → Basic**: set **App Domains** (`azulzin.com.br`), a **Privacy Policy URL**, and a
  contact email. Copy the **App ID** and **App Secret**.
- **Facebook Login → Settings → Valid OAuth Redirect URIs** — add (byte-exact):
  ```
  http://localhost:3000/auth/facebook/callback
  https://azulzin.com.br/auth/facebook/callback
  ```
- **App Roles → Roles**: add teammates as Admin/Developer/Tester — only these can log in until
  the app is approved.

## 2. App Review for `email`

- **App Review → Permissions and Features** → request **Advanced Access** for `email`.
- Meta requires at least one successful Graph API call first, then submit with a short
  screencast of the login flow. Pin a Graph API version.
- Until approved, testing is limited to the roles above.

## 3. Credentials (when Phase 5 is implemented)

```yaml
facebook:
  app_id: "1234567890"
  app_secret: xxxxxxxxxxxxxxxx
```

(via `bin/rails credentials:edit`.)

## 4. Code that Phase 5 will add

- `provider :facebook, …, scope: "email", info_fields: "email"` in `config/initializers/omniauth.rb`
- broaden the callback route constraint to `/google_oauth2|facebook/`
- a Facebook `button_to` on sign-in + sign-up (i18n)

**Important — account linking:** `User.provider_email_verified?` returns `false` for Facebook
(Facebook does not assert a verified email), so a Facebook login **never** auto-links to an
existing password account and **never** auto-confirms — it creates a new, unverified user (or,
if the email collides with an existing account, the unique index rejects it and the callback
shows a friendly "add an email" alert). This is intentional; see [ADR 0002](decisions/0002-omniauth-social-login-and-account-linking.md).
