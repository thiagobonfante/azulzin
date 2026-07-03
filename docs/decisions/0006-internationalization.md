# 6. Internationalization: pt-BR default, en-US supported

## Status

Accepted (2026-07-03)

## Context

azulzin's first public is Brazil, but the product must support English (US) speakers from the start rather than retrofit i18n later (retrofitting hardcoded strings, currency, and mailers is the expensive path). We are simultaneously building the accounts/authentication feature, so the locale preference can be added to the `users` table at no extra migration cost, and every auth string/mailer can be authored through `I18n` from day one.

Decisions to settle: the locale set and codes, how the active locale is resolved and switched, how money/dates are formatted for a finance app, and how emails pick a language.

Stack: Rails 8.1, Ruby 3.4, Hotwire/Turbo (server-rendered), PostgreSQL, Kamal. Rails ships `config/locales/en.yml` only; no i18n gems yet.

## Decision

Adopt Rails' built-in i18n with the `rails-i18n` locale-data gem.

- **Locales:** `default_locale = :"pt-BR"`; `available_locales = [:"pt-BR", :"en-US", :en]`; `fallbacks = [:en]`. `rails-i18n` ships a real `en-US.yml` (a thin regional override of the base `:en`), so `:"en-US"` is a first-class UI locale and `:en` is loaded **only** as the fallback base — never offered as a choice. App strings live under `pt-BR:` and `en:` keys; `:"en-US"` inherits English via BCP-47 dash-split fallback (no duplication). Never use `fallbacks = true` (it would fall back to `pt-BR` and show Portuguese to English users).
- **Locale resolution & switching (Strategy A — no locale in URLs):** an `ApplicationController` `around_action` wraps each request in `I18n.with_locale`, resolving in order `params[:locale]` → `session[:locale]` → `current_user&.locale` → `Accept-Language` (via `http_accept_language`), **whitelisted** against `config.x.supported_locales` and defaulting to `pt-BR`. A `users.locale` column (`string, null: false, default: "pt-BR"`, added with the accounts migration) persists a logged-in member's choice across devices; a `LocalesController#update` (`PATCH /locale`) writes the preference (and `session[:locale]` for guests). We do **not** scope routes by locale.
- **Money & numbers (finance-critical):** store money as **integer cents** and format with `BigDecimal` + `number_to_currency`, which pulls the symbol/format from the active locale (`R$ 1.234,56` for pt-BR, `$1,234.56` for en-US). Never hardcode `R$`/`$` or parse pt-BR decimals with `to_f`.
- **Mailers:** `ApplicationMailer` sets the locale from `params[:user].locale` inside an `around_action`, so verification/reset emails render in the recipient's language regardless of the enqueuing request's locale. Subjects come from locale files via `default_i18n_subject`; a single view per mailer uses `t(".…")`.
- **Tooling:** `i18n-tasks` lints for missing/unused keys and gates CI so pt-BR and en stay in sync.

## Consequences

- Every user-facing string across the app (starting with the accounts feature) must be a translation key from the first commit — enforced as a project rule in `CLAUDE.md`.
- New gems: `rails-i18n`, `http_accept_language`, and `i18n-tasks` (development/test).
- The `around_action` + `I18n.with_locale` pattern is mandatory — a bare `I18n.locale =` assignment leaks the locale across requests on threaded Puma.
- A stale `<html lang>` can persist after a Turbo-driven in-place locale switch, so the language switcher forces a full navigation (`data: { turbo: false }`).
- `config.time_zone` is independent of locale; set it explicitly if Brasília timestamps are wanted.
- Adding a third locale later (e.g. `es`, `en-GB`) is now cheap: add the file + one entry to `supported_locales`.

## Alternatives considered

- **Locale-prefixed URLs (`/pt-br`, `/en-us`)** — better for public SEO/shareable localized pages, but adds routing/`default_url_options` plumbing to every path (including the just-planned auth routes) and is harder to retrofit off. Overkill for a logged-in personal-finance app. Rejected; revisit only if a public marketing surface needs indexed per-language URLs.
- **Session/cookie toggle only (no `users.locale`, no `Accept-Language`)** — simplest, but the preference doesn't follow a user across devices and first-time guests always start in pt-BR. Barely less code than Strategy A once a `users` table exists. Rejected.
- **Label `:en` as "English (US)"** — avoids defining `:"en-US"`, but yields `<html lang="en">` and misses the explicit en-US requirement. Rejected in favor of a real `:"en-US"` locale.
- **`money-rails` gem** — richer money modeling, unnecessary at this scale; integer cents + `number_to_currency` suffices. Rejected as speculative.
