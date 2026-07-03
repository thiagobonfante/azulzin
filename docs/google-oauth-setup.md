# Google OAuth setup

How to enable "Continue with Google" (Phase 4). The app code is already in place —
`config/initializers/omniauth.rb` reads `credentials.dig(:google, :client_id/:client_secret)`
and the callback lives at **`/auth/google_oauth2/callback`**. You only need to create the
OAuth client in Google Cloud Console and add the two secrets to Rails credentials.

## 1. Create the OAuth client (Google Cloud Console)

Go to <https://console.cloud.google.com> and select or create a project (e.g. **azulzin**).

**a) Consent screen** — open **Google Auth Platform** (older consoles: *APIs & Services → OAuth consent screen*). First time → **Get started**:
- **Branding**: App name `azulzin`, user support email, developer contact email. Logo/domain optional.
- **Audience**: **External**. Starts in **Testing** status → only accounts added under **Test users** can sign in; add your own Google account. (Publish later — see Notes.)
- **Data Access → Add scopes**: `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`. These are **non-sensitive** → **no Google verification review** is required. This is exactly why we chose email/profile.

**b) Client** — **Clients → Create client**:
- **Application type**: `Web application`
- **Name**: `azulzin web` (internal label)
- **Authorized redirect URIs** — add both, *byte-exact* (or Google returns `redirect_uri_mismatch`):
  ```
  http://localhost:3000/auth/google_oauth2/callback
  https://azulzin.com.br/auth/google_oauth2/callback
  ```
  (Authorized JavaScript origins are not needed — this is a server-side flow.)
- **Create** → copy the **Client ID** (`…apps.googleusercontent.com`) and **Client secret** (`GOCSPX-…`).

No API needs enabling — omniauth-google-oauth2 uses the OpenID Connect userinfo endpoint.

## 2. Add the secrets to Rails credentials

```bash
EDITOR="code --wait" bin/rails credentials:edit    # or EDITOR=vim / nano
```

Add (keep the existing `resend:` entry; YAML is space-indented, no tabs):

```yaml
google:
  client_id: 1234567890-xxxx.apps.googleusercontent.com
  client_secret: GOCSPX-xxxxxxxxxxxxxxxx
```

Save + close → `config/credentials.yml.enc` is re-encrypted. Commit that file (encrypted, safe); `config/master.key` stays git-ignored.

## 3. Verify + test

```bash
# both keys decrypt (prints true/true — no secret is shown)
bin/rails runner 'puts Rails.application.credentials.dig(:google,:client_id).present?; puts Rails.application.credentials.dig(:google,:client_secret).present?'

bin/rails server   # restart so the OmniAuth middleware picks up the creds
```

Visit **http://localhost:3000/session/new** (use `localhost`, not `127.0.0.1` — Google only whitelists `localhost` for http) → **"Continuar com o Google"**. First login creates a confirmed `User` + an `oauth_identity`; a second login reuses the same account (see `User.from_omniauth` and [authentication.md](authentication.md)).

## Notes / gotchas

- **`redirect_uri_mismatch`** → the console URI doesn't exactly match the request (scheme/host/port/path). Path is `/auth/google_oauth2/callback`; dev host is `http://localhost:3000`.
- **Testing vs Published**: in *Testing* only listed Test users can log in. Scopes are non-sensitive, so you can **Publish** (Audience → Publish app) for instant public access with no review.
- Credential changes require a **server restart** (middleware is built at boot).
- **Production** needs `RAILS_MASTER_KEY` on the server to decrypt these — already wired into Kamal (`.kamal/secrets` + `config/deploy.yml` `env.secret`).
- Account linking: a Google login whose email matches an existing password account is linked **only because Google asserts the email is verified** (`email_verified`). See [ADR 0002](decisions/0002-omniauth-social-login-and-account-linking.md).
