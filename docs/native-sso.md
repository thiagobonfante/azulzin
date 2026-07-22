# Native SSO (Google + Apple in the iOS/Android shells)

How social sign-in works inside the Hotwire Native apps. The web's OAuth redirect flow
([authentication.md](authentication.md) §OAuth) is **impossible in the shells**: Google
returns `403 disallowed_useragent` for OAuth inside embedded webviews. Instead, the
shells obtain a provider **ID token** via the platform SDKs and the page exchanges it
for a normal Rails session. Plan/build history: `.plans/mobile/10-google-sso-and-referral.md`.

## The flow

1. **Reveal** — `sessions/_native_sso.html.erb` renders hidden buttons on the native
   variant of the sign-in/registration screens. The `bridge--sign-in` Stimulus
   controller ([app/javascript/controllers/bridge/sign_in_controller.js]) is a
   `BridgeComponent`; it only activates when the shell registered the `sign-in`
   component (advertised in the User-Agent), and its `connect()` un-hides the buttons.
   Plain webviews and old app builds keep email/password untouched.
2. **Native leg** — a tap sends `signIn {provider}` over the bridge. iOS
   (`SignInComponent.swift`) runs the GoogleSignIn SDK or `ASAuthorizationController`
   (Apple, no SDK); Android (`SignInComponent.kt`) runs Credential Manager +
   `googleid`. The reply carries `{idToken}`; cancel/failure sends **no reply** and the
   page stays put.
3. **Exchange** — the Stimulus controller builds a real `<form>` POST (CSRF token from
   the page meta tag, `data-turbo-action="replace"`) to `POST /auth/:provider/token`
   (route-constrained to `google_oauth2|apple`). The **webview itself makes the POST**,
   which is what lands the session cookie in the webview — no cookie transfer, no
   external browser round-trip.
4. **Verify + session** — `TokenSessionsController` → `Auth::IdToken.verify` → wraps
   the payload in an `OmniAuth::AuthHash` (`provider` + `uid = sub`, matching what the
   web flow writes to `OauthIdentity`) → the **same** `User.from_omniauth` path as the
   web: identity lookup, verified-email-only linking, random-password creation,
   invitation-aware bootstrap, allowlist gate via `start_new_session_for`.

Because provider + uid match the web flow, a user who signed in with Google on the web
lands in the same account on mobile, and vice-versa.

## Token verification (`app/services/auth/id_token.rb`)

The trust boundary. Verifies with the `jwt` gem against the provider's **public JWKS**
(cached 12h in `Rails.cache`, refetched once on unknown `kid`): RS256 signature, `exp`,
`iss`, and an `aud` whitelist:

| Provider | `iss` | Accepted `aud` |
|---|---|---|
| `google_oauth2` | `accounts.google.com` (both forms) | web client id (credentials `google.client_id` — Android tokens carry this, it's Credential Manager's `serverClientId`) + iOS client id (credentials `google.ios_client_id`) |
| `apple` | `https://appleid.apple.com` | bundle id `br.com.azulzin.app` (constant; a web Services ID would join it) |

Unconfigured provider (empty aud list) or any decode failure → `nil` → generic
"could not sign in" alert. Real-crypto tests: `test/services/auth/id_token_test.rb`
(forged key, wrong aud/iss, expired, garbage — all refused). Endpoint tests:
`test/controllers/token_sessions_controller_test.rb` (mirrors the OmniAuth callback
suite incl. allowlist + unverified-email refusal). Rate limit 10/3min like sessions.

`User.provider_email_verified?` accepts `google_oauth2` **and** `apple`
(`email_verified` arrives as `true` or `"true"` depending on provider/era). Apple
private-relay addresses are verified by construction.

## Per-platform wiring

**iOS** (`native/ios/app/app/`): `SignInComponent.swift` registered in the AppDelegate.
GoogleSignIn is SPM-added and compiled behind `#if canImport(GoogleSignIn)` (same
pattern as Firebase) — without the package or with an empty `Config.googleClientID`
the Google tap is a no-op; Apple works with zero config (AuthenticationServices + the
`com.apple.developer.applesignin` entitlement). The reversed-client-id URL Type must
live in **BOTH** `Info-Debug.plist` and `Info-Release.plist` — each serves only its own
build configuration; missing the Release one breaks Google sign-in **only in
TestFlight/App Store builds**. `SceneDelegate.scene(_:openURLContexts:)` forwards to
`GIDSignIn.handle`.

⚠️ **Privacy-cover guard**: the SSO sheet resigns the scene active, which used to slam
the biometric lock cover over the session and kill it (symptom: a glimpse of the sheet,
then a stuck blue logo). `sceneWillResignActive` skips the cover while
`SignInComponent.externalAuthInFlight` — the same doctrine as the `authenticating`
guard for the Face ID sheet. Any future external-auth surface needs the same treatment.

**Android** (`native/android/.../SignInComponent.kt`): Credential Manager with
`GetGoogleIdOption(serverClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID)` (the **web**
client id, set in `app/build.gradle.kts`). No Apple on Android (the web only renders
that button for the iOS UA). Google validates the calling app by **package + signing
SHA-1** against registered Android OAuth clients — one client per certificate (debug
keystore, upload key, **Play App Signing key**). A missing Play-App-Signing client
makes SSO fail *only* in Play-distributed builds (`DEVELOPER_ERROR`/no credential).

**Why Apple at all**: App Store Guideline 4.8 — an iOS app offering Google login must
offer Sign in with Apple (email/password does not satisfy it).

## Config surface

| Value | Lives in |
|---|---|
| Google web client id | credentials `google.client_id` (aud for Android tokens) + `GOOGLE_WEB_CLIENT_ID` in `native/android/app/build.gradle.kts` |
| Google iOS client id | credentials `google.ios_client_id` + `Config.googleClientID` + reversed form as the URL scheme in both iOS plists |
| Apple | nothing — public JWKS, bundle-id constant, entitlement in `app.entitlements` |

## Status & what's missing

- ✅ iOS **Google** flow: live smoke passed on the simulator (2026-07-21).
- ⬜ iOS **Apple** flow: code complete, not yet smoke-tested (needs a signed-in Apple
  ID on the device/simulator).
- ⬜ **Android** flow: compiles, not yet smoke-tested (needs a Play-services emulator
  image with a Google account + `adb reverse tcp:3000 tcp:3000`).
- ⬜ **Play App Signing SHA-1** Android OAuth client not yet created (Play Console →
  Setup → App signing → certificate SHA-1). Without it, store builds fail SSO.
- ⛔ **Web Sign in with Apple**: deliberately skipped — needs a Services ID, a .p8 key
  with client-secret rotation, and carries a known SameSite/`form_post` callback wart.
  Revisit only if wanted; the native flow does not depend on it.
- E2E: the native exchange is pinned by integration tests (`native_variant_test.rb` +
  the two suites above); it cannot ride the browser E2E lanes (no native SDK there).
