
# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Project Rules — azulzin

### Internationalization (i18n) — the app is bilingual

**azulzin is a Brazil-first product: `pt-BR` is the default locale and `en-US` is fully supported. Every user-facing string ships as a translation key — no hardcoded UI text, ever.**

- **Locales:** default `:"pt-BR"`; also support `:"en-US"`. `:en` is loaded only as the fallback base and is never offered as a UI choice. Always whitelist locale input against the supported set (`config.x.supported_locales`).
- **All user-facing text goes through `I18n`** — views/controllers use lazy lookup `t(".key")`; model names, attributes, and validation errors live under the `activerecord.*` namespaces; mailer subjects/bodies are keyed too. Self-check on every diff: grep views/controllers/mailers for quoted human-readable strings — there should be none.
- **Money, dates, and numbers are localized, never hardcoded.** Format currency with `number_to_currency` (the locale renders `R$ 1.234,56` vs `$1,234.56`); store money as integer cents and format with `BigDecimal`, never floats. Never hardcode `R$`/`$` or a date format.
- **Locale is per-request only.** Set it with `around_action` + `I18n.with_locale` — a bare `I18n.locale =` leaks across requests on Puma. Resolve in order: `params` → `session` → `current_user.locale` → `Accept-Language`, always whitelisted, defaulting to `pt-BR`.
- **Emails render in the recipient's language.** Mailers set the locale from the stored `user.locale` *inside* the mailer (via `around_action`), not from the caller's ambient locale.
- **Keep locale files in sync.** Adding a key to one locale means adding it to the other; `i18n-tasks` (missing/unused-key lint) gates CI.
- **⚠️ TEMPORARY launch pin (since 2026-07):** production currently pins `pt-BR` in code — `ApplicationController#resolve_locale` and `ApplicationMailer#set_locale` hardcode `I18n.default_locale`, so en-US is unreachable in every env. The bilingual rules above remain the contract (keep shipping keys in both locales); do NOT "fix" the pin in passing. Lifting it is a product decision and must restore the full resolve chain AND build the en-US E2E golden matrix + mailer-locale tests (follow-up recorded in `.plans/e2e/05-web-journeys.md` §8).
- Details: [docs/i18n.md](docs/i18n.md) · decision: [ADR 0006](docs/decisions/0006-internationalization.md).

### E2E tests — user journeys are pinned end to end

**Any change to a money path, a WhatsApp reply, a notification, or a user-facing journey ships with (or updates) an E2E scenario.** The suite lives in `test/e2e/` + `test/system/journeys/`; the full manual is [docs/e2e-testing.md](docs/e2e-testing.md) — read it before writing an E2E test.

- **Pick the cheapest lane that proves the behavior.** Lane P (`E2E::PipelineCase`): real webhook → jobs → fake-sidecar HTTP + signed-cookie web requests — the default. Lane B (`E2E::BrowserCase` / `test/system/journeys/`): only for behavior that needs a real browser (Turbo Streams UX, stimulus pickers). Lane C (node `fake.js` contract parity): don't add to it unless the sidecar envelope itself changes; run with `E2E_SIDECAR=node`.
- **Seed with scenario packs, never ad-hoc fixtures:** `E2E::Scenario.build(:solo_basic | :couple | :full_house | :goal_active | :goal_cuts …)` — calibrated frozen cents with build-time self-checks. New recurring shape → add a pack + self-check, don't inline it twice.
- **Stub ONLY the AI boundary** (`with_canned_ai` → real `Whatsapp::Extraction` structs). Everything else — HTTP, jobs, DB, money math — runs real. `travel_to` always (anchor `E2E.anchor`); assert exact centavos, never ranges.
- **Golden bodies:** user-visible WhatsApp/notification copy is pinned as the full pt-BR body (`assert_wa_reply equals: I18n.t(...)` or heredoc). Changing reply copy = re-render and re-pin the golden, deliberately.
- **Browser-lane discipline (anti-flake):** after any Turbo form submit, wait on a UI change (flash/path/selector) **before** touching the DB; after driving a stimulus picker, assert its button display updated before the next action.
- **Spec vs code disagreement:** never assert behavior that doesn't exist. Pin the REAL behavior with a comment naming the gap, and flag it in [.plans/e2e/07-coverage-audit.md](.plans/e2e/07-coverage-audit.md) for a product decision.
- **Scenario IDs** (`WA-CAP-nn`, `NT-GL-nn`, `WEB-…`, `MU-…`) come from the catalogs in `.plans/e2e/03–05`; keep the ID comment on every test so coverage stays auditable.

### Mobile — every feature is a three-front feature (web, WhatsApp, native shells)

**The iOS/Android apps (`native/ios`, `native/android`) wrap the SAME server-rendered HTML — so every new page, interaction, or feature is framed mobile-first-class from the start.** Most work is automatically shared; what isn't must be explicitly checked against the shells. Details: `.plans/mobile/handoff.md`.

- **Every user-facing page renders in BOTH layouts**: web (`app.html.erb`) and chrome-less native (`app.html+native.erb`). Native gets its title from `content_for :title` (shown in the nav bar) — an in-page `h1` that duplicates it gets `data-native-dup` (hidden under `.native-shell`). Dashboard-style greetings that aren't dups stay.
- **Platform CSS truth**: body carries `.native-shell` + `.native-android`/`.native-ios`. iOS's floating tab bar really overlaps the webview → `env(safe-area-inset-bottom)` padding is REAL there; Android reports a PHANTOM bottom inset → zero it (see application.css overrides). Any new bottom-pinned UI (bars, FABs, sheets) must handle both, and must live inside `<main>` or pad env() itself.
- **New routes** → check `PathConfigurationsController::RULES` (modal vs push; auth pages MUST stay `context: default`) and regenerate BOTH bundled copies on any rules change: `bin/rails runner 'puts JSON.pretty_generate({settings: {}, rules: PathConfigurationsController::RULES})'` → `native/ios/app/app/path-configuration.json` + `native/android/app/src/main/assets/json/configuration.json`.
- **Native-surface features** (mic, camera, push, share, biometric, downloads, external links) need shell code in BOTH `native/ios` and `native/android`, shipped in lockstep — never one platform ahead.
- **Verify shell-affecting changes by DRIVING the simulator/emulator with screenshots** (recipes + gotchas in the handoff), not just tests; `test/integration/native_variant_test.rb` pins the layout/path-config contract. Emulator ghost-pixels are a known GPU artifact — check the DOM before chasing them.
