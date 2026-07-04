# The product app: onboarding, accounts, cards & dashboard

How the authenticated product surface works, and how to extend it. Decisions and rationale live in [ADR 0008](decisions/0008-app-onboarding-accounts-and-cards.md).

## Layouts

| Layout | Used by | Looks like |
| --- | --- | --- |
| `application` | marketing + auth pages | top header + footer (public chrome) |
| `app` | dashboard, Contas, Cartões | sidebar (Painel/Contas/Cartões) + user menu |
| `onboarding` | the wizard | centered, focused, step progress bar |

All three share the `<head>` via `app/views/layouts/_meta.html.erb`.

## The first-run flow

```text
sign in ─▶ app root (/) ─▶ /dashboard ─▶ require_onboarding? ─▶ /onboarding
                                                  │ onboarded
                                                  ▼
                                            dashboard renders
```

- `PagesController#home` sends a signed-in visitor on the app host to `/dashboard`.
- `AppController#require_onboarding` (inherited by `DashboardController`) redirects to `/onboarding` until `current_user.onboarded?`.
- `OnboardingController` drives three route-constrained steps: `profile → accounts → cards`.
  - `GET /onboarding` (no step) redirects to `resume_step` — the earliest incomplete step. Deep links cannot jump ahead of it.
  - **profile**: `name` + `phone` (required, `:profile` validation context; phone normalized to `55…`).
  - **accounts**: `PATCH /onboarding/accounts` only advances with **≥1 bank account**.
  - **cards**: optional; `PATCH /onboarding/cards` sets `onboarded_at` and lands on the dashboard.

Accounts and cards are added/removed by `BankAccountsController` / `CreditCardsController` (used both in the wizard and from the sidebar), which answer **Turbo Streams** (`create`/`destroy` update the list in place) with an HTML redirect fallback for no-JS.

## Adding / editing an institution

`config/institutions.yml` is the single source of truth (COMPE code, name, initials, brand color, position).

- **Add a bank:** add a line to the YAML, then `bin/rails db:seed` (idempotent). Tests pick it up automatically (the fixture is generated from the same YAML).
- **Add a real logo:** drop a self-contained, square-ish SVG at `app/assets/images/institutions/<code>.svg`, then re-seed. `logo_path` is derived from the file's presence, so the `institution_avatar` helper switches from the monogram to the logo with no other change. Monochrome glyphs should use `fill="currentColor"` (they get the brand color); multicolor logos keep their own fills.
- "Outro/OTHER" is code `000` — a real row, always the FK fallback; its name is the only localized one (`institutions.other`).

## Money

- Stored as integer **cents** (`*_cents`). Never use floats for money.
- Forms use a `*_reais` virtual field (from the `MoneyColumns` concern) → `Money.to_cents` parses `1.234,56` / `1,234.56` / `1234`.
- Display with `brl(cents)` (`MoneyHelper`) → `number_to_currency`. Never hardcode `R$`.
- Credit cards: store limit + current bill; `available_cents` and `usage_ratio` are derived.

## i18n

- Every user-facing string is a key in **both** `config/locales/pt-BR.yml` and `en.yml`; `bin/rails runner` / `i18n-tasks` (CI) enforce parity and no unused keys. New activerecord model/attribute names live under `activerecord.*`.
- The UI is currently **pinned to pt-BR** (`ApplicationController#resolve_locale`).
- `MoneyHelper#brl` pins the `R$` unit (`money.symbol`) so amounts render `R$` in every UI language — Rails' `en` currency default is `$`, so without this reais would show as dollars under en-US. Only separators localize. No extra work is needed when en-US is re-enabled.

## Tests

- `test/fixtures/institutions.yml` is an **ERB fixture generated from `config/institutions.yml`**, so the test registry never drifts.
- `test_helper.rb` sets `PGGSSENCMODE=disable`: macOS libpq's GSSAPI negotiation is not fork-safe and segfaults parallel test workers. Harmless and cross-platform.
- Coverage: `test/models/{money,institution,bank_account,credit_card,user}_test.rb` and `test/controllers/{onboarding,bank_accounts,credit_cards,dashboard}_controller_test.rb`.
