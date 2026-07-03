# azulzin

**Calm, simple control over your money.** *Azul(zin)* — "little blue" — a personal
finance app designed to feel gentle and clear enough for anyone to use.

This repository currently holds the **initial back/front architecture**: a working
Rails 8 skeleton wired to PostgreSQL, styled with Tailwind CSS v4 + daisyUI under a
custom blue theme, with a landing/dashboard preview at `/`. Domain features
(accounts, transactions, budgets) are intentionally *not* built yet — the ground is
prepared for them.

## Stack

- **Language** — Ruby 3.4.7
- **Framework** — Rails 8.1
- **Database** — PostgreSQL 16
- **CSS** — Tailwind CSS v4 (`tailwindcss-rails`, standalone — no Node build)
- **UI kit** — daisyUI v5 with a custom `azulzin` light + dark theme
- **JS** — Hotwire (Turbo + Stimulus) via importmap
- **Jobs / cache / cable** — Solid Queue, Solid Cache, Solid Cable
- **Deploy** — Kamal + Thruster (scaffolded, not configured)

## Prerequisites

- Ruby 3.4.7 (pinned in `.tool-versions` / `.ruby-version`)
- PostgreSQL reachable on `localhost:5432` with a `postgres` / `postgres` role
  (any Postgres works — see [Configuration](#configuration) to point elsewhere)

## Getting started

```bash
# 1. Install the pinned Ruby (asdf/rbenv) and gems
asdf install            # or: rbenv install 3.4.7
bundle install

# 2. Create and prepare the databases
bin/rails db:prepare

# 3. Run the app (starts Rails + the Tailwind watcher via foreman)
bin/dev
```

Then open <http://localhost:3000>.

> `bin/dev` runs both the web server and the Tailwind CSS watcher. If you only need
> the server, `bin/rails server` works too — just rebuild CSS with
> `bin/rails tailwindcss:build` after changing styles or markup.

## Configuration

Development and test connect to Postgres using these environment variables, with
sensible defaults so the app runs out of the box:

- `DATABASE_HOST` — default `localhost`
- `DATABASE_PORT` — default `5432`
- `DATABASE_USERNAME` — default `postgres`
- `DATABASE_PASSWORD` — default `postgres`

Override any of them to point at a different Postgres, e.g.
`DATABASE_PASSWORD=secret bin/dev`.

## Design system

The visual identity lives in [`app/assets/tailwind/application.css`](app/assets/tailwind/application.css):

- **`azulzin`** — the default light theme: a friendly azure primary (the *azul*) on a
  faintly-blue near-white base, with money-green / money-red for cash in/out.
- **`azulzin-dark`** — the same identity after dark, applied automatically via the
  visitor's OS `prefers-color-scheme`.

Colors are defined in the `oklch` color space. Type pairs **Bricolage Grotesque**
(display / wordmark) with **Inter** (body and tabular money figures).

## Testing

```bash
bin/rails test          # unit + controller tests
bin/rails test:system   # system tests (headless browser)
```

## Project layout highlights

```
app/
  assets/tailwind/application.css   # Tailwind + daisyUI + azulzin theme
  controllers/pages_controller.rb   # the landing/dashboard page
  views/pages/home.html.erb         # hero + signature balance card
  views/layouts/application.html.erb# shell: navbar, fonts, footer
config/
  database.yml                      # env-driven Postgres config
  routes.rb                         # root -> pages#home
```

## Next steps

The architecture is ready for the first real domain slice — e.g. an `Account` and
`Transaction` model, a form to record income/expenses, and turning the preview
balance card into live data.
