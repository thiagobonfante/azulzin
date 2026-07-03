
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
- Details: [docs/i18n.md](docs/i18n.md) · decision: [ADR 0006](docs/decisions/0006-internationalization.md).
