# 8. Product app: onboarding wizard, accounts & cards data model, and the institution registry

## Status

Accepted (2026-07-04)

## Context

With auth, the marketing/app host split (ADR 0007), and production email in place, the product needed its own authenticated surface — distinct from the marketing page. The first-run experience is a setup wizard, after which the user lands on a dashboard. We had to decide: how the app shell differs from marketing, how onboarding is modelled and gated, the data model for bank accounts and credit cards, how Brazilian financial institutions (and their logos) are represented, and how money is captured/stored/displayed under the pt-BR-first i18n rules.

## Decision

### App shell & routing

- Two new layouts: `app` (a daisyUI `drawer` **sidebar** — Painel / Contas / Cartões + a user menu) for the dashboard and management pages, and `onboarding` (a focused, centered wizard shell with a step progress bar). Both share `<head>` via `layouts/_meta` extracted from the marketing layout. Marketing keeps `application`.
- `AppController < ApplicationController` sets `layout "app"` + `before_action :require_onboarding`. `DashboardController` inherits it. The onboarding gate and `on_app_host?` live in `ApplicationController` (private) so the accounts/cards controllers can require onboarding on their `index` only (they are also used *inside* the wizard, where onboarding is not yet complete).
- The app-host root redirects a signed-in visitor to `/dashboard` (`PagesController#home`), which in turn redirects to the wizard until onboarding is complete.

### Onboarding wizard

- Server-driven steps (`onboarding/:step`, `step ∈ {profile,accounts,cards}`, route-constrained), no SPA. `onboarding` (no step) resolves to the earliest incomplete step (`resume_step`); deep links cannot jump ahead of it.
- **profile** (required): `name` + `phone`, validated only in the `:profile` context so sign-up/OAuth creation (which never touch them) stay unaffected. Phone is normalized to E.164-ish digits with the `+55` country code prepended, ready for WhatsApp.
- **accounts**: at least **one** bank account is required to finish (product decision); details are optional.
- **cards**: optional.
- Completion is recorded by `users.onboarded_at`; `require_onboarding` redirects everyone else into the wizard.

### Institutions — a seeded entity keyed by COMPE code

- `institutions` is a **database table** (not an in-memory list), because the COMPE **bank code must be a first-class persisted attribute** for future integrations (Open Finance / Pix / reconciliation). Columns: `code` (unique, indexed), `name`, `initials`, `brand_color`, `logo_path` (nullable), `supports_account`/`supports_card`, `position`.
- The canonical list lives in `config/institutions.yml` (single source of truth). `Institution.load_registry!` upserts it idempotently by `code` (stable ids) from `db/seeds.rb`; the test DB loads it through an **ERB fixture** generated from the same YAML (`test/fixtures/institutions.yml`) so it can never drift.
- `bank_accounts` and `credit_cards` reference the institution by FK. "Outro/OTHER" (code `000`) is a real seeded row so the FK is always valid; its display name is the only localized one.

### Institution logos

- **Vendored real SVG logos** (9: Nubank, Itaú, Santander, Mercado Pago, PicPay, Banco XP, Banco Pan, Banco BV, Sicoob) under `app/assets/images/institutions/<code>.svg`; every other institution falls back to a **brand-color monogram** (initials + contrast-aware text). One helper, `institution_avatar`, renders either — it inlines the SVG so monochrome glyphs pick up the brand color via `currentColor`.
- `logo_path` is **derived from the presence of the SVG file** at seed time, so adding a bank's logo later is: drop the file in, re-seed. No schema or data change.

### Money

- Stored as **integer cents** (`*_cents` bigint), never floats. Forms accept/show a human string through a `*_reais` virtual accessor (`MoneyColumns` concern); `Money.to_cents` tolerantly parses pt-BR (`1.234,56`), en-US (`1,234.56`) and plain input.
- Credit cards store `credit_limit_cents` + `current_bill_cents` (the next-bill/used amount); **available credit is derived** (`limit − bill`), and `usage_ratio` drives the utilization bar.
- Display goes through `number_to_currency` (`MoneyHelper#brl`, BigDecimal), never a hardcoded `R$`. The unit is `R$` because the money is always BRL; separators localize per locale.

## Consequences

- The bank code is persisted and joinable, ready for later financial integrations without a migration.
- The accounts/cards controllers serve both the wizard and post-onboarding management (sidebar Contas/Cartões) with Turbo Streams and an HTML redirect fallback; the picker degrades to a native `<select>` via `<noscript>`.
- Adding an institution = edit one YAML file (+ optionally drop an SVG). Tests, seeds, and prod stay in sync automatically.
- **en-US currency:** `MoneyHelper#brl` pins the `R$` unit (`money.symbol`) rather than inheriting it from the locale, so amounts render `R$` in every UI language (Rails' `en` currency default is `$`); only the separators localize. Nothing extra is needed when en-US is re-enabled.
- **Test infrastructure:** macOS libpq GSSAPI negotiation is not fork-safe and segfaults parallel test workers; `PGGSSENCMODE=disable` is set in `test_helper` (harmless, cross-platform).

## Alternatives considered

- **In-memory PORO institution registry (no table).** Simpler, but the user explicitly required the entity to persist the bank code for the future; a table makes the code a first-class, queryable, joinable column. Chosen the table.
- **Brand-color monograms only (no real logos).** CSP-safe and license-clean, but less recognizable. Chosen a hybrid: real vendored SVGs where a clean square symbol exists, monogram fallback everywhere else — same `logo_path` mechanism, upgradeable with no data change.
- **Storing `institution_code` string on accounts/cards instead of an FK.** Resilient but denormalized; an FK to the seeded entity is cleaner and the code is reachable via the association. Chosen the FK.
- **Skippable accounts step.** Lower friction, but leaves the first dashboard empty. Chosen "≥1 account required" (cards stay optional).
- **Slim top-bar shell.** Simpler, but the sidebar reads more as a product and gives Contas/Cartões destinations. Chosen the sidebar.
- **Client-side wizard (SPA/Turbo Frames only).** More moving parts; server-driven steps are simpler, testable, and robust. Chosen server-driven steps with Turbo Streams only for the add/remove interactions.
