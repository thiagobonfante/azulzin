# 7. Host-based split: marketing on the apex, product app on app.azulzin.com.br

## Status

Accepted (2026-07-03)

## Context

azulzin is a single Rails 8 monolith. The public marketing landing (`pages#home`) and the authenticated product (sessions, registrations, passwords, email verification, Google OAuth) share one codebase, one layout, and — until now — one domain. We want the public site to answer on the apex `azulzin.com.br` (plus `www`) and the product to answer on `app.azulzin.com.br`.

The app has never been deployed: `config/deploy.yml` still carries the Rails generator's placeholder IP. It will run on a single Ubuntu host behind an already-configured **Cloudflare Tunnel** (`cloudflared`), which terminates TLS at Cloudflare's edge and forwards HTTP to the local Puma/Thruster origin. The product is pre-launch — there is no dashboard yet; the only real product pages are auth.

The choice was between two deployments (extract the marketing site onto the apex, deploy the Rails app only on the subdomain) and one app that routes by `Host` header.

## Decision

Keep **one Rails app and one deploy**; separate the two surfaces by hostname.

- **Route constraints (`config/routes.rb`).** Two lambda constraints, `on_app` and `on_marketing`, gate the route groups. `on_app` matches `app.azulzin.com.br`; `on_marketing` matches `azulzin.com.br` and `www.azulzin.com.br`. In **development and test both return `true`**, so everything is served on one origin (`localhost`) and the existing test suite and dev workflow are untouched. Shared routes (`PATCH /locale`, `/up`, `/robots.txt`) sit outside both groups and answer on every host.
- **Two roots at `/`.** The apex root is `root "pages#home"`; the app host gets `get "/", to: "pages#home", as: :app_root` (a distinct name to avoid a route-name collision). Both render the marketing page for now — the app host root becomes a dashboard once one exists. Path helpers generate `/` for both, so relative in-app links keep working; only cross-host links need an absolute URL.
- **Cross-host CTAs (`app_url` helper).** The public marketing chrome (header "sign in" / "get started", hero CTA) is rendered on the apex, where the auth routes do **not** exist. `ApplicationHelper#app_url(path)` prefixes such links with `https://app.azulzin.com.br` in production and returns the relative path in development.
- **Emails link to the app host.** `config.action_mailer.default_url_options[:host]` is `app.azulzin.com.br` (not the apex), because verification and password-reset links resolve to app-host routes. The mailer already renders in the recipient's stored locale (ADR 0006).
- **OAuth on the app host.** The Google authorized redirect URI is `https://app.azulzin.com.br/auth/google_oauth2/callback`; the sign-in that initiates OAuth lives on the app host, so the callback host is consistent.
- **Session cookies stay app-scoped.** The signed `session_id` cookie is set with no `domain:` option, so it is confined to `app.azulzin.com.br`. The apex has no authentication and always renders the logged-out marketing chrome — no cross-subdomain cookie sharing is introduced.
- **Host hardening.** `config.hosts` is set to the three real hostnames (DNS-rebinding protection), with `/up` excluded from host authorization so the tunnel's health probe passes. `assume_ssl` + `force_ssl` remain on and rely on `cloudflared` forwarding `X-Forwarded-Proto: https`.
- **Host-aware `robots.txt`.** Served from `PagesController#robots` (removed from `public/`, which would otherwise shadow the route): the apex is crawlable; `app.azulzin.com.br` returns `Disallow: /`.
- **Edge routing.** The Cloudflare Tunnel maps all three hostnames to the **same** local origin; Rails distinguishes them by the `Host` header. No `kamal-proxy`/Let's Encrypt is used — the tunnel owns TLS.

## Consequences

- One image, one deploy, one database — the least infrastructure for a pre-launch product, consistent with the project's simplicity-first rule.
- Any new authenticated feature must be added inside the `on_app` constraint block; a new public marketing page goes in `on_marketing`. Cross-host links from marketing must go through `app_url`, not a bare path helper (a bare path would 404 on the apex in production).
- Splitting into a separate marketing deployment later is still possible, but the host boundary and cross-host link helper are already in place, so the pressure to do so is low.
- The Google console redirect URI, Cloudflare SSL/TLS mode (Full), and the tunnel ingress are operational steps outside the repo; they are documented in `docs/google-oauth-setup.md` and the deploy runbook.
- Because dev/test are single-origin, host-specific behavior (the 404-on-apex split) is only exercised in production; a regression there would not be caught by the current tests. Verified manually via `recognize_path_with_request` against both hosts.

## Alternatives considered

- **Two deployments (separate marketing site on the apex, Rails only on the subdomain).** Cleaner separation and independent scaling, but two build/deploy pipelines and duplicated chrome for a product with a one-view marketing site and no traffic yet. Rejected as premature; revisit if marketing grows its own stack or team.
- **`kamal-proxy` + Let's Encrypt for TLS.** The Rails 8 default, but it duplicates what the existing Cloudflare Tunnel already provides and would fight the tunnel over TLS termination. Rejected in favor of the tunnel.
- **Subdomain-shared session cookie (`domain: ".azulzin.com.br"`).** Would let a login "follow" a user from apex to app, but the apex has no auth surface to benefit and it widens the cookie's blast radius. Rejected; revisit only if the marketing site ever needs to read auth state.
- **Environment-branched route file (`if Rails.env.production?`).** Equivalent behavior, but branching the whole route DSL on the environment is harder to read than two constraint lambdas that short-circuit in dev/test. Rejected.
