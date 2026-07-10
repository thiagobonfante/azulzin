# E2E testing

How the end-to-end suite works and how to extend it. Full design rationale lives in
`.plans/e2e/` (gitignored); this is the operating manual.

## Running

```sh
bin/rails test test/e2e                 # Lane P: pipeline E2E (also runs inside plain `bin/rails test`)
bin/rails test:system                   # Lane B: browser journeys (test/system/journeys) + legacy system tests
E2E_SIDECAR=node PARALLEL_WORKERS=1 \
  bin/rails test test/system/journeys/contract_sidecar_test.rb   # Lane C: real node fake.js (also nightly CI)
```

## Architecture — three lanes

- **Lane P** (`test/e2e/`, `E2E::PipelineCase`): the webhook envelope is POSTed with real
  bearer auth, jobs drain explicitly, and outbound replies travel a **real socket** into
  `E2E::FakeSidecarServer` — an in-process Rack stand-in for the sidecar contract, booted
  per test worker on an ephemeral port (`WHATSAPP_SERVICE_URL` is a per-call ENV read, so
  each worker points at its own). Fast, fully parallel.
- **Lane B** (`test/system/journeys/`, `E2E::BrowserCase`): Capybara/headless Chrome
  against the real Puma server; `wa_inject` posts the webhook over a real socket to that
  same server. Assert **server-rendered** content only — Chrome's clock is not traveled.
- **Lane C** (`contract_sidecar_test.rb`): five smokes against the actual
  `node whatsapp-sidecar/fake.js` (spawned on a free port, webhooking back into the
  Capybara server). CT-01 pins envelope parity between fake.js and `wa_inject`, so the
  Ruby fake can never silently drift from the real contract. Runs nightly
  (`.github/workflows/e2e-contract.yml`) and on demand.

## Scenarios — one account per test

`E2E::Scenario.build(:pack)` (`test/test_helpers/e2e/scenario.rb`) seeds a fresh account
through the same service objects production uses, with **fixed calibrated cents** — no
randomness. Key packs:

| pack | contents / calibration |
|---|---|
| `bare` | owner + solo account + default categories, nothing else |
| `solo_basic` | + Itaú checking, Nubank card (due 10 / closes the 3rd), salary R$ 5.000,00 day 5 |
| `wa_verified!(consent:)` | decorator: verified WhatsApp identity (+ push consent) |
| `couple` | + second member, both verified |
| `history_calibrated` | 3 full months + current: Mercado 88,3% (warn) · Restaurantes 108% (breach) · Transporte exactly 80% · Lazer 79,997% (silent) · Vestuário median R$ 420,00 · guardado R$ 300,00/mês. Self-checks its own calibration at build time |
| `cards_billing` | purchases straddling the closing date + a 10× R$ 349,90 installment |
| `reminders_due` | bills due/overdue arranged around the traveled today |
| `goal_active(paid:)` | active goal via the real `Goals::Activate`, backdated 2 months; `paid:` ratios steer the pace band |

Rules: every test runs inside `travel_to` (default `E2E.anchor` — Wednesday 12:00 SP,
mid-month); packs contain nothing the scenario doesn't assert; changing a calibrated cent
is a breaking change to every test asserting it. Two goals must never share a caixinha
(each counts the other's transfers as progress) — pass `into:` a second savings account.

## The only stubbed boundary: AI

`with_canned_ai(extraction:/transcript:/receipt:)` + `E2E::CannedAI` builders return real
`Whatsapp::Extraction` structs — the LLM's *classification* is canned, all money math
stays in Ruby, same as production. Everything else (webhook auth, jobs, models, views,
outbound HTTP) runs real. An unstubbed AI call in a test will attempt real HTTP — stub it.

## Goldens

Proactive WhatsApp bodies are asserted as **full literal strings** (see
`test/e2e/notifications/`). A failing golden means either a bug (fix the code) or an
intentional copy change — update the golden in the same commit, re-reading it as a user
would. Never rebuild a golden by re-calling I18n with the same args.

## Gotchas

- `Notification.period_key` is a **date** column — string keys cast to nil.
- Frozen clock: a balance re-anchor and a row created at the same instant don't order —
  `travel 1.minute` between them.
- Partial goal months must `MarkPaid(amount:)`, not a bare transfer — an unpaid
  occurrence keeps projecting and `RiskScan` reads the month red.
- pt-BR CSV exports are BOM-prefixed and `;`-separated.
- Capybara's `assert_no_text` takes no message argument.
- The code-attempt cap and unknown-sender throttle live in `Rails.cache` (null store in
  test) — swap in a `MemoryStore` via `Rails.stub(:cache, …)` to exercise them.
