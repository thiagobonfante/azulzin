# Exploratory testing handbook

Manual, end-to-end walkthroughs for every user-facing journey — WhatsApp capture, goals,
reminders/budgets/summaries, web ledger, multi-user, imports, auto-categorization — happy
**and** unhappy paths. Each scenario names the seed that prepares its data, the exact action
to perform (message to type, URL to open, or `bin/rails runner` line to fire), and the
observable outcome. The automated E2E suite ([docs/e2e-testing.md](e2e-testing.md)) pins the
same behaviors with stubbed AI; this handbook is for what automation can't feel — real AI
calls, real browser UX, real time.

## Coverage index

**2. WhatsApp — identity & expense capture** — 28 scenarios
`WA-ID-01` · `WA-ID-02` · `WA-ID-04` · `WA-ID-05` · `WA-ID-06` · `WA-ID-07` · `WA-ID-09` · `WA-CAP-01` · `WA-CAP-06` · `WA-CAP-03` · `WA-CAP-04` · `WA-CAP-07` · `WA-CAP-08` · `WA-CAP-10` · `WA-CAP-15` · `WA-CAP-16` · `WA-CAP-17` · `WA-CAP-19` · `WA-EXP-02` · `WA-CAP-21` · `WA-CAP-23` · `WA-CAP-24` · `WA-CAP-33` · `WA-EXP-01` · `WA-CAP-22` · `WA-CAP-30` · `WA-CAP-31` · `WA-CAP-25`

**3. Goals — creation, checks, replan, celebrate** — 30 scenarios
`WA-GOAL-01` · `GL-EXP-01` · `WA-GOAL-02` · `WA-GOAL-03` · `WA-GOAL-04` · `WA-GOAL-06` · `WEB-GOAL-02` · `GL-EXP-02` · `WA-GOAL-07` · `WEB-GOAL-01` · `WEB-GOAL-03` · `WEB-GOAL-09` · `WEB-GOAL-10` · `WEB-GOAL-11` · `NT-GL-01` · `NT-GL-02` · `NT-GL-11` · `NT-GL-03` · `NT-GL-04` · `NT-GL-12` · `NT-GL-09` · `NT-GL-07` · `NT-GL-08` · `NT-GL-13` · `WA-GOAL-05` · `WEB-GOAL-05` · `GL-EXP-03` · `WEB-GOAL-04` · `WEB-GOAL-06` · `WEB-GOAL-07`

**4. Reminders, budgets, summaries & the notification spine** — 28 scenarios
`NT-R-01` · `NT-R-02` · `NT-R-07` · `NT-R-03` · `NT-R-05` · `NT-B-01` · `NT-B-04` · `NT-B-05` · `NT-B-06` · `NT-B-07` · `NT-B-08` · `NT-S-01` · `NT-S-02` · `NT-S-03` · `NT-G-03` · `NT-G-06` · `NT-G-07` · `NT-G-05` · `NT-G-10` · `WA-ID-09` · `NT-X-02` · `NT-X-04` · `NT-G-12` · `NT-X-03` · `WEB-EXP-02` · `WEB-TX-08` · `WA-CAP-12` · `NT-EXP-01`

**5. Web journeys — auth, onboarding, ledger, instruments** — 40 scenarios
`WEB-AUTH-01` · `WEB-AUTH-02` · `WEB-AUTH-03` · `WEB-AUTH-04` · `WEB-AUTH-05` · `WEB-AUTH-06` · `WEB-ONB-01` · `WEB-ONB-02` · `WEB-ONB-03` · `WEB-ONB-05` · `WEB-EXP-11` · `WEB-TX-01` · `WEB-TX-02` · `WEB-TX-03` · `WEB-TX-04` · `WEB-TX-05` · `WEB-TX-06` · `WEB-TX-07` · `WEB-TX-08` · `WEB-TX-09` · `WEB-TX-10` · `WEB-TX-11` · `WEB-EXP-12` · `WEB-EXP-13` · `WEB-BANK-01` · `WEB-BANK-02` · `WEB-BANK-03` · `WEB-CARD-01` · `WEB-CARD-02` · `WEB-CARD-03` · `WEB-CARD-04` · `WEB-EXP-14` · `WEB-EXP-15` · `WEB-EXP-16` · `WEB-EXP-17` · `WEB-EXP-18` · `WEB-DASH-01` · `WEB-DASH-02` · `Account settings & LGPD deletion (see §6)` · `I18N-02`

**6. Multi-user — invites, attribution, LGPD deletion** — 17 scenarios
`MU-01` · `MU-EXP-01` · `MU-02` · `MU-03` · `MU-EXP-02` · `MU-04` · `MU-10` · `MU-EXP-03` · `MU-EXP-04` · `MU-EXP-05` · `MU-EXP-06` · `MU-09` · `MU-06` · `MU-05` · `MU-07` · `MU-EXP-07` · `MU-08`

**7. Document imports — extrato/fatura → proposals → apply** — 18 scenarios
`WEB-IMP-01` · `IMP-EXP-01` · `IMP-EXP-02` · `WEB-IMP-02` · `WEB-IMP-03` · `WEB-IMP-04` · `WEB-IMP-05` · `WEB-IMP-06` · `WEB-IMP-07a` · `WEB-IMP-07b` · `WEB-IMP-07c` · `IMP-EXP-03` · `WEB-IMP-08` · `WEB-IMP-09` · `WEB-IMP-10` · `IMP-EXP-04` · `IMP-EXP-05` · `IMP-EXP-06`

**8. Auto-categorization — memory, LLM piggyback, backfill** — 12 scenarios
`WA-CAP-01` · `CAT-EXP-01` · `WA-CAP-17` · `CAT-EXP-02` · `CAT-EXP-03` · `CAT-EXP-04` · `WEB-TX-11` · `WEB-TX-11b` · `CAT-EXP-05` · `CAT-EXP-06` · `CAT-EXP-07` · `CAT-EXP-08`

**9. Cross-cutting — tenancy, errors, mobile, retention, admin** — 20 scenarios
`WEB-ADM-01` · `WEB-ADM-02` · `X-EXP-01` · `WEB-ADM-03` · `X-EXP-02` · `WA-CAP-29` · `X-EXP-12` · `X-EXP-13` · `I18N-03` · `X-EXP-03` · `X-EXP-04` · `X-EXP-05` · `X-EXP-06` · `X-EXP-07` · `X-EXP-08` · `X-EXP-09` · `X-EXP-10` · `NT-R-06` · `X-EXP-11` · `X-EXP-14`

**Total: 193 scenarios.** IDs without `-EXP-` come from the automated E2E catalogs (`.plans/e2e/03–05`); `*-EXP-*` IDs are exploratory-only (no automated twin yet). A few catalog IDs appear in two chapters on purpose — each chapter tests a different facet.

## 1. Setup & conventions

### 1.1 The stack

```sh
bin/dev-fake        # Rails :3000 + FAKE WhatsApp simulator :3001 (no QR, no Chromium)
```

- **http://localhost:3000** — the app. **http://localhost:3001** — the WhatsApp simulator:
  pick a prefilled number or click **+ adicionar número** and type the digits (the UI appends
  `@c.us`). It sends text, uploaded images/PDFs, and recorded audio through the same webhook
  envelope the real sidecar uses; Rails believes it is talking to a live, connected sidecar.
- Emails never leave the machine — `letter_opener` pops them in a browser tab.
- Everything is pt-BR: the launch pin hardcodes the locale in every env (deliberate — don't
  "fix" it; see CLAUDE.md).

### 1.2 Seeding: one test account per scenario shape

Every numbered seed **wipes and recreates** `test-N@azulzin.dev` (password `test1234`) with a
calibrated data shape, reusing the same `E2E::Scenario` packs the automated suite pins — so
the cents you see manually are the cents the tests assert.

```sh
bin/rails exploratory:list          # the registry
bin/rails "exploratory:seed[4]"     # (re)seed one scenario — always safe to re-run
bin/rails exploratory:seed_all      # all of them
bin/rails "exploratory:wipe[4]"     # remove one
bin/rails dev:seed_demo             # the rich Família Andrade demo (marina/rafael@azulzin.dev, demo1234)
```

| N | login (`/test1234`) | contents |
|---|---|---|
| 1 | test-1@azulzin.dev | WA capture: Itaú + Nubank card + caixinha + salário; **WA-verified**; merchant memory ready (3× "iFood"→Restaurantes) |
| 2 | test-2@azulzin.dev | Phone **not** verified; AZUL- code minted and printed by the seed |
| 3 | test-3@azulzin.dev (+ test-3b) | Couple, both WA-verified, partner has own card |
| 4 | test-4@azulzin.dev | Calibrated budgets: Mercado 88,3% WARN · Restaurantes 108% BREACH · Transporte 80,000% WARN · Lazer 79,997% silent; + 6 uncategorized rows for backfill |
| 5 | test-5@azulzin.dev | Reminders: Condomínio due tomorrow · Luz overdue 2d (grace) · Água overdue 5d (outside) · fatura closes tomorrow · Freela tomorrow |
| 6 | test-6@azulzin.dev | Goal "Carro" active 2 months, on track `[1,1,1]` |
| 7 | test-7@azulzin.dev | Goal at risk — contributions trimmed to 93% of TODAY's expected (re-seed on the test day) |
| 8 | test-8@azulzin.dev | Goal off track `[1,0.5,0]` (50%) |
| 9 | test-9@azulzin.dev | Goal cap R$ 400,00 < standing budget R$ 600,00; spend R$ 340,00 |
| 10 | test-10@azulzin.dev | No goal; caixinha + income history — ready to CREATE a goal (WA chat or web) |
| 11 | test-11@azulzin.dev | Clean instruments for document imports |
| 12 | test-12@azulzin.dev | Confirmed user, onboarding wizard never run |
| 13 | test-13@azulzin.dev (+ test-13b) | Invites: owner + a separate invitee who owns a data-bearing solo account |
| 14 | test-14@azulzin.dev | Tenancy canary: R$ 666,66 "VAZAMENTO LTDA" — must never leak into another account |
| 15 | test-15@azulzin.dev | Goal exactly R$ 50,00 short of target — one contribution triggers the 🎉 |

WA-verified seeds print their JID (e.g. `5511910000001@c.us`) — add that number in the
simulator to chat as that user.

> ⚠ **Goal seeds (6/7/8/15) read best between the 6th and 25th** of the month: the packs
> assume payday (day 5) has passed. The seed prints a warning otherwise.

### 1.3 Kicking scheduled jobs (nothing recurs in dev)

`config/recurring.yml` only schedules in production. WhatsApp inbound processing runs by
itself (in-process `:async` adapter), but every sweep is manual:

```sh
bin/rails runner 'Reminders::DailyDispatchJob.perform_now'      # bill/income/fatura reminders
bin/rails runner 'Budgets::WeeklyCheckDispatchJob.perform_now'  # budget bands sweep
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'    # goal pace / predictive warnings
bin/rails runner 'Goals::ApplyBudgetCutsJob.perform_now'        # writes goal plan cuts into budgets
bin/rails runner 'Summaries::WeeklyDispatchJob.perform_now'     # weekly digest
bin/rails runner 'Summaries::MonthlyDispatchJob.perform_now'    # month recap
```

Always use `perform_now` — `perform_later` dies with the runner process on the async adapter.

### 1.4 Reading notification outcomes

A notification "arrived" in two tiers:
1. **The Notification row** (dashboard bell/banner) — always written. This is the reliable observable.
2. **The WhatsApp push** — only when ALL hold: `whatsapp_consent` ON (`/notification_preferences`),
   phone verified, sidecar connected (fake is always green), inside 08–21 America/São_Paulo,
   daily push cap not hit. Outside quiet hours the push is withheld, the row still lands.

### 1.5 AI: live, deterministic, or forced-broken

- **Live AI in dev**: extraction/vision (OpenRouter) and STT (Groq) really fire. Scenarios
  tagged `AI: live-AI` need the keys and tolerate model wobble — assert the *shape* (posted vs
  parked vs asked), the money regexes keep cents exact.
- **Deterministic (no AI)**: AZUL- verification, `apaga`/`desfaz` undo, `parar` stop,
  reorganizar keyword, slot-fill replies, all web flows, all sweeps.
- **Forced failure**: restart the stack as `OPENROUTER_API_KEY=broken bin/dev-fake` (or
  `GROQ_API_KEY=broken`) to test the degrade paths deterministically — every scenario tagged
  `AI: broken-key`. Restore the real key afterwards.

### 1.6 Odds and ends

- Dev cache is per-process `:memory_store`: unknown-sender throttles and the 10-guess code cap
  reset on server restart; cache writes from a `runner` process are invisible to the server.
- Envelopes the simulator UI can't produce (oversized-media flag, replayed message ids, forced
  disconnect) go straight to the webhook:
  ```sh
  curl -s localhost:3000/api/whatsapp/webhook \
    -H 'Authorization: Bearer dev-whatsapp-token' -H 'Content-Type: application/json' \
    -d '{"event":"message_received","data":{"from":"5511910000001@c.us","message_id_serialized":"manual_1","type":"text","body":"padaria 12,50 no débito no itaú"}}'
  ```
- Scenario IDs follow the E2E catalogs (`WA-CAP-nn`, `NT-GL-nn`, `WEB-…`, `MU-…`,
  `.plans/e2e/03–05`); `*-EXP-nn` IDs are exploratory-only (no automated twin yet).
- When a scenario documents behavior that *disagrees with the spec*, it pins the REAL behavior
  and flags the gap — same discipline as the automated suite.
## 2. WhatsApp — identity & expense capture

This chapter walks the whole inbound WhatsApp pipeline: identity (verification, throttles, idempotency, consent), then text capture and its verbs (corrections, undo), audio, image/PDF receipts, and the deterministic degrade paths. It leans on `bin/rails dev:seed_demo` (Marina `5511987654321@c.us` and Rafael `5511976543210@c.us`, both prefilled in the :3001 simulator) plus `exploratory:seed[1]` (pre-armed merchant memory), `seed[2]` (unverified phone + printed AZUL code) and `seed[3]` (clean-room couple). Stack for every scenario: `bin/dev-fake` (Rails :3000 + fake simulator http://localhost:3001). Verify outcomes via simulator replies + `bin/rails runner` — the webhook always returns 200.

### WA-ID-01 — Verification handshake: unknown JID texts its AZUL code

Seed: `exploratory:seed[2]` · AI: deterministic

**Steps:**
1. Run `bin/rails "exploratory:seed[2]"` — note the AZUL- code it PRINTS (e.g. `AZUL-7K3M`).
2. Open http://localhost:3001, click "+ adicionar número", type `5511910000002` (the UI appends `@c.us`).
3. Send: `meu código é AZUL-7K3M` (use the printed code — mid-sentence works, the scan is whole-token).
4. Verify: `bin/rails runner 'u=User.find_by!(email_address:"test-2@azulzin.dev"); puts u.phone_verified_at, u.whatsapp_jid'`

**Expect:** Reply "WhatsApp ativado! ✅ Agora é só me mandar seus gastos por aqui." The user gets `phone_verified_at` set, `whatsapp_id` = digits, `whatsapp_jid` = `5511910000002@c.us`, code cleared. NO WhatsappMessage row is persisted (the handshake short-circuits before storage).

Demo-seed alternative (mints a fresh code for Marina):
```
bin/rails runner 'u=User.find_by!(email_address:"marina@azulzin.dev"); u.update!(phone_verified_at: nil, whatsapp_id: nil, whatsapp_jid: nil); puts u.whatsapp_verification_code!(force: true)'
```

**Variants:**
- WA-ID-03 phone_already_linked: needs the ambiguous-JID setup — two verified users on 9th-digit variants of the same number so `verified_for_wa` refuses, then a third user's code texted from that phone hits the unique `whatsapp_id` index → reply "Este número já está vinculado a outra conta no azulzin..."; sender stays unverified. Set up the variant pair via `bin/rails runner`.
- Wrong code (e.g. `AZUL-ZZZZ`) → deterministic feedback, never silence (WA-ID-12/13, added 2026-07-11): sender digits match a registered phone → "Código inválido. Confira o código no app e tente de novo."; completely unknown number → "Número não cadastrado no azulzin. Se cadastre no app primeiro. 💙". A typo that breaks the `AZUL-` token (e.g. `ZUL-VGXU`) is NOT code-shaped and still rides the generic unknown-sender throttle.

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:73-86`, `app/models/user.rb:154-187`, `config/locales/pt-BR.yml:1361`

### WA-ID-02 — 9th-digit JID tolerance: digit-dropped variant still resolves

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Run `bin/rails dev:seed_demo` (Marina verified as `5511987654321`, 13 digits with the 9).
2. In the simulator add the variant WITHOUT the 9: `551187654321`.
3. Send: `apaga o último` (deterministic undo pre-pass — proves resolution + reply routing with zero AI).
4. Check: `bin/rails runner 'puts User.find_by(email_address:"marina@azulzin.dev").whatsapp_jid'`

**Expect:** The message resolves to Marina (`wa_id_candidates` adds/drops the 9), gets a reply in HER chat variant ("Não achei nada recente pra desfazer." if she has no fresh WA rows), and her `whatsapp_jid` is refreshed to the variant JID.

Pins: `app/models/user.rb:192-209`, `app/controllers/api/whatsapp/webhooks_controller.rb:43`

### WA-ID-04 — Code-guess brute force cap: 10 code-shaped guesses per JID per day

Seed: `exploratory:seed[2]` · AI: deterministic

**Steps:**
1. Run `bin/rails "exploratory:seed[2]"` — note the printed correct code. Dev cache is `:memory_store`, so the counter holds until server restart.
2. From `5511910000002` in the simulator send 10 wrong codes (`AZUL-AAAA`, `AZUL-AAAB`, … vary the 4 chars).
3. Send the CORRECT code as the 11th message the same day.
4. Restart `bin/dev-fake` and send the correct code again.

**Expect:** Guesses 1–10: each replies "Código inválido. Confira o código no app e tente de novo." (the JID matches test-2's registered phone; an unknown number would get the "Se cadastre no app primeiro" nudge instead — WA-ID-12/13). The 11th (correct) code is IGNORED SILENTLY — `code_attempt_over_cap?` returns true, no reply, no verification. After the restart (memory cache reset) the code verifies normally.

**Variants:**
- Non-code-shaped text from the same JID is never counted against the cap (regex gate `/AZUL-[A-Z0-9]{4}/i`) — an expense text still gets the unknown-sender treatment.

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:71-97`

### WA-ID-05 — Unknown sender throttle: unregistered phone texts an expense

Seed: none (any dev DB) · AI: deterministic

**Steps:**
1. In the simulator add `5511888887777` (never verified).
2. Send: `mercado 54,90`.
3. Immediately send a second message, anything.

**Expect:** First message: reply "Número não cadastrado no azulzin." exactly once. Second message inside the 6h window: SILENCE (Rails.cache `unless_exist` throttle). No WhatsappMessage rows, no transactions, no job in the log — no AI call fires (short-circuits before the job).

**Variants:**
- Group JID: add `120363041234567890@g.us` and send text — there is no group filter in the webhook; it resolves as unknown sender and the throttled "Número não cadastrado" goes TO THE GROUP JID. Flag as a product gap if the real sidecar forwards group messages.
- Throttle reset: restart Rails (memory_store cache) → the same JID gets the reply again — confirms the window is per-process, not durable.

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:39-41`, `app/services/unknown_sender_reply.rb:6-16`, `config/locales/pt-BR.yml:1360`

### WA-ID-06 — Oversized media envelope: sidecar flags media_too_large

Seed: `dev:seed_demo` · AI: deterministic

The fake UI cannot set this flag — hit the Rails webhook directly with the shared bearer.

**Steps:**
1. Run:
```
curl -s localhost:3000/api/whatsapp/webhook -H 'Authorization: Bearer dev-whatsapp-token' -H 'Content-Type: application/json' -d '{"event":"message_received","data":{"from":"5511987654321@c.us","message_id_serialized":"manual_big_1","type":"image","body":"","media_too_large":true}}'
```
2. Watch Marina's chat in the simulator and the Rails log.

**Expect:** Reply "Esse arquivo é muito grande para eu ler. Pode reenviar uma foto ou PDF menor?" NO WhatsappMessage row created, no job enqueued (check log).

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:47,104-107`, `config/locales/pt-BR.yml:1356`

### WA-ID-07 — Webhook redelivery idempotency: same message_id_serialized twice

Seed: `dev:seed_demo` · AI: live-AI

The fake UI mints fresh ids every send, so replay via curl with a fixed id.

**Steps:**
1. Run this identical command TWICE:
```
curl -s localhost:3000/api/whatsapp/webhook -H 'Authorization: Bearer dev-whatsapp-token' -H 'Content-Type: application/json' -d '{"event":"message_received","data":{"from":"5511987654321@c.us","message_id_serialized":"replay_test_1","type":"text","body":"padaria 12,50 no débito no itaú"}}'
```
2. Count rows: `bin/rails runner 'puts WhatsappMessage.where(wa_message_id: "replay_test_1").count'` and check the ledger.

**Expect:** Exactly ONE WhatsappMessage, ONE job run, ONE transaction (1250 centavos), ONE reply bubble. Second delivery: `find_or_create_by` hits the existing row, `previously_new_record?` false → no enqueue; webhook still returns 200.

**Variants:**
- WA-ID-08 wrong bearer: same curl with `Authorization: Bearer wrong-token` → 401, nothing persisted, nothing enqueued, no reply.

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:49-66`, `app/services/whatsapp/decider.rb:79`

### WA-ID-09 — Stop consent: "parar" kills proactive notifications, never capture replies

Seed: `dev:seed_demo` · AI: deterministic (stop) + live-AI (follow-up expense)

**Steps:**
1. From Marina's chat send: `parar` (also try `para de me avisar`).
2. Then send: `mercado 30 no débito no itaú` (needs live OPENROUTER key).

**Expect:** First: deterministic regex pre-pass (zero LLM) replies "Prontinho, parei os avisos por aqui. É só reativar em *Conta e membros → Avisos* quando quiser. 💙" and `notification_prefs.whatsapp_consent` flips false. Second: the expense STILL posts and STILL gets its ✅ reply — consent gates only `Notifications::Deliver`, never capture confirmations.

**Variants:**
- `gastei 50 sem parar` must NOT trigger stop (anchored regex) — it rides the normal expense pipeline.
- Re-enable is in-app only: toggle at http://localhost:3000/notification_preferences — there is no WA re-enable phrase.

Pins: `app/services/notifications/stop_command.rb:12-22`, `app/services/whatsapp/interpreter.rb:31`, `app/services/notifications/deliver.rb:32`, `config/locales/pt-BR.yml:1397`

### WA-CAP-01 — Text auto-commit happy path + merchant-memory category

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Marina's chat: `mercado pão 54,90 no débito no itaú`.
2. In the web hub (login marina@azulzin.dev / demo1234) set that transaction's category to Mercado by hand (human edit → `category_source` 'user' → memory armed).
3. Send: `mercado pão 33,50 no débito no itaú`.

**Expect:** Each posts a transaction with EXACT centavos (5490 / 3350), instrument = Itaú (Marina), `source_message_id` set. Reply pattern "✅ Lançado: R$ 54,90 na conta Itaú (Marina)." — the second capture's reply appends " · Mercado" (posted_account_categorized), proving the memory chain. Balance moves on the dashboard (HYB-01).

**Variants:**
- WA-CAP-02 ambiguous instrument (method-narrowed since 2026-07-11, WA-CAP-02b/c/d/e): the payment method narrows the candidates — credito → cards, debito/pix → checking accounts (caixinha never listed); with método desconhecido the PHRASE narrows instead ("cartão" → cards, "conta" → checking accounts), since a bare "no cartão" honestly extracts as desconhecido. ONE candidate → assigns silently (closing rule applied for cards). TWO+ → numbered ask "Anotei R$ 60,00 👍 Qual cartão? Responde com o número:\n1. …" and the zero-LLM answer (`2` or a name) posts on the pick. Only an UNKNOWN method (`gastei 50 no posto`, dinheiro/boleto) still posts UNASSIGNED with "✅ Lançado: R$ 50,00. Escolha a conta ou o cartão no app.". Ask expires in 60min like any slot ask.
- Live-AI caveat: extraction quality is the real model's — merchant/instrument phrasing may vary run to run; the cents math (`Money.to_cents` in Ruby) is deterministic.
- Fast lane: `exploratory:seed[1]` arrives with memory pre-armed (3× user-categorized "iFood"→Restaurantes on a WA-verified owner) — skip steps 1–2 and capture an iFood expense to see the memory hit immediately.

Pins: `app/services/whatsapp/interpreter.rb:35-37,69-74`, `app/services/whatsapp/decider.rb:27-50`, `config/locales/pt-BR.yml:1346-1349`

### WA-CAP-06 — Money format matrix through the real pipeline

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Marina, three separate messages: `farmácia 1.234,56 no débito no itaú` / `farmácia 1234,56 no débito no itaú` / `farmácia R$ 15 no débito no itaú`. Note (2026-07-11): messages 1 and 2 resolve to the SAME cents+merchant, so the second triggers the duplicate ask (WA-CAP-35) — reply `sim` to post it and continue the matrix.

**Expect:** Rows with exactly 123456 / 123456 / 1500 centavos (LLM returns `amount_raw` verbatim; Ruby `Money.to_cents` converts). Replies quote localized R$ 1.234,56 / R$ 1.234,56 / R$ 15,00.

Pins: `app/services/whatsapp/extractor.rb:110-113`, `app/services/whatsapp/decider.rb:83`

### WA-CAP-03 — Low-confidence park lands in the pending tray

Seed: `dev:seed_demo` · AI: live-AI

Deterministic trick: restart `bin/dev-fake` with `WHATSAPP_CONFIDENCE_FLOOR=101` (env read once at class load) so EVERY extraction parks; or keep the default floor 80 and send genuinely vague text, relying on the live model's honesty.

**Steps:**
1. With floor=101, from Marina: `mercado 84,90 no débito no itaú`. (With default floor: `acho que gastei uns 40 ontem em alguma coisa`.)
2. In the browser: check the pending tray badge, confirm the row from the tray.

**Expect:** Transaction status `pending_review` (instrument match KEPT if strong — pre-routed in the tray), reply "Recebi 👍 Deixei pendente no app para você revisar." Confirming from the tray → posted (HYB-02).

> Verbatim-amount exception (2026-07-11, WA-CAP-03b): a terse message whose amount appears
> literally in the text (`33 cartao`) no longer parks on a low OVERALL score — a verbatim
> amount can't be hallucinated, so the amount field confidence alone gates it. Hedged
> amounts (`acho que gastei uns 40`) still park via their low amount-field score, and the
> `WHATSAPP_CONFIDENCE_FLOOR=101` trick still parks everything (verbatim caps at 100).

**Variants:**
- WA-CAP-27 gibberish WITHOUT amount: `asdfgh qwerty` → intent other, no amount → help menu golden ("Não entendi 🤔 Você pode me mandar coisas como: …"). With an amount buried in gibberish → parks.
- WA-CAP-28 mutating intent below the 0.75 intent floor with an amount parks a `pending_review` stub instead of firing the verb (interpreter.rb:86-89) — live-AI dependent, not deterministically triggerable.

Pins: `app/services/whatsapp/confidence.rb:11-12,24-31`, `app/services/whatsapp/decider.rb:52-58`, `config/locales/pt-BR.yml:1353`

### WA-CAP-04 — Missing amount → "quanto foi?" ask → zero-LLM slot-fill reply

Seed: `dev:seed_demo` · AI: live-AI (first message only; the answer routes zero-LLM)

**Steps:**
1. From Marina: `gastei no mercado no débito no itaú` (no amount).
2. Wait for the ask, then reply: `54,90`.
3. Watch the Rails log during step 2 — no new extraction call.

**Expect:** Ask reply "Não consegui identificar o valor. Quanto foi?"; a `needs_clarification` row exists (amount 0, ask slot=amount, expires in 60min, instrument pre-resolved). The `54,90` answer posts the SAME row at 5490 centavos with "✅ Lançado: R$ 54,90 na conta Itaú (Marina)."

**Variants:**
- Unparseable answer (`sei lá`) → re-ask clarify_amount, row stays open.
- WA-CAP-05 expiry: age the ask, then reply `54,90` → treated as a FRESH message (rides the full pipeline, likely parks or asks anew); the stale ask row stays unresolved.
```
bin/rails runner 'Transaction.open_ask_for(User.find_by!(email_address:"marina@azulzin.dev")).update_columns(ask_expires_at: 2.minutes.ago)'
```

Pins: `app/services/whatsapp/decider.rb:63-69`, `app/jobs/process_inbound_whatsapp_job.rb:72-74`, `app/services/whatsapp/reply_router.rb:28-43`, `app/models/transaction.rb:117-122`

### WA-CAP-07 — Income capture: "recebi o salário"

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Marina: `recebi o salário, 5000` (demo seed carries recurring incomes "Salário Marina" → Itaú, "Salário Rafael" → Nubank).

**Expect:** Income row 500000 centavos linked to the recurring income on Itaú; reply "💙 Recebido: R$ 5.000,00 em Itaú (Marina)." (income_posted_linked) — or income_posted if the link heuristic misses. Dashboard entradas move.

**Variants:**
- Income with no instrument/recurring match (account-narrowed since 2026-07-11, WA-CAP-07b/c): `caiu 1200 de um freela` — a sole checking account self-picks silently ("💙 Entrou: R$ 1.200,00 em Itaú."); several get the numbered "Anotei R$ 1.200,00 👍 Em qual conta entrou?" pick (caixinha never listed). income_posted_unassigned only remains reachable with zero checking accounts.

Pins: `app/services/whatsapp/interpreter.rb:48`, `app/services/whatsapp/income_decider.rb:1`, `config/locales/pt-BR.yml:1363-1365`

### WA-CAP-08 — Transfer to caixinha: "guardei 300 na caixinha"

Seed: `dev:seed_demo` · AI: live-AI

Demo seed has a single savings account "Caixinha" (→ savings_default resolves it); Itaú + Nubank checking make the FROM leg ambiguous.

**Steps:**
1. From Marina: `guardei 300 na caixinha`.
2. When the numbered ask arrives, answer: `1`.

**Expect:** Numbered ask "De qual conta saiu? Responde com o número:\n1. …" — the answer posts ONE transfer row, 30000 centavos, legs from-account → Caixinha, no category, reply "💙 Guardado: R$ 300,00 na Caixinha. Boa!". Guardado total on the dashboard +300.

**Variants:**
- WA-CAP-09 destination ask: `transferi 300 do itaú` (no destination) → ask_transfer_to numbered options; picking the SAME account as the other leg re-asks (reply_router.rb:52-54).
- Answering with an out-of-range number or a name that fuzzy-matches nothing → re-ask with the same options.

Pins: `app/services/whatsapp/transfer_decider.rb:12-44`, `app/services/whatsapp/reply_router.rb:45-85`, `config/locales/pt-BR.yml:1366-1369`

### WA-CAP-10 — Card installments: "notebook 3.499,00 em 10x no nubank"

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Rafael's chat (`5511976543210@c.us`): `comprei um notebook, 3.499,00 em 10x no nubank`.
2. Verify parcels in the web card bill screens.

**Expect:** Installments::Create: 10 parcels summing EXACTLY 349900 centavos (centavo-exact split), staggered across faturas; reply "✅ Parcelado: 10x de R$ 349,90 em <card>. Primeira parcela na fatura de <mês>."

**Variants:**
- WA-CAP-11 uneven split: `700,05 em 7x no nubank` → 7 parcels summing exactly 70005 centavos (no lost centavo).
- Missing count: `comprei parcelado um sofá de 1200 no nubank` → ask "Em quantas vezes?" → reply `6` (or `seis`) resolves zero-LLM. Valid range is 1–24 (2026-07-11): `1` is accepted (a single fatura charge), 25+ re-asks; an extraction that already CARRIES an out-of-range count (`em 30x`) parks for review (WA-CAP-10d).
- No card named (`1000 parcelado`, WA-CAP-10b/c): parcelado is always credit — a sole card self-picks silently; several cards get the numbered "Qual cartão?" pick, which CHAINS into "Em quantas vezes?" when the count is missing too. Both answers are zero-LLM.
- WA-CAP-13 debit installment: `sofá 1.680,00 em 6x no débito no itaú` → Commitment (kind installment) 6 × 28000 centavos, reply installment_commitment_created.
- Undo teardown: right after posting, `apaga o último` tears down the WHOLE plan → "🗑️ Desfeito: parcelamento de 10x de R$ 349,90 em <card>." (undo_handler.rb:36-44).

Pins: `app/services/whatsapp/installment_decider.rb:1`, `app/services/whatsapp/reply_router.rb:87-103`, `config/locales/pt-BR.yml:1370-1373`

### WA-CAP-15 — Pay commitment: "paguei a parcela" with ambiguous pick

Seed: `dev:seed_demo` · AI: live-AI

Demo seed already carries multiple commitments (Notebook installment on Itaú card, Sofá installment on Itaú account, fixed bills, subscriptions).

**Steps:**
1. From Marina: `paguei a parcela` (ambiguous).
2. When the numbered ask arrives, reply: `2`.
3. Then the direct form: `paguei a parcela do sofá`.

**Expect:** Ambiguous: "Qual deles? Responde com o número:\n1. …" — a bare/generic phrase ("a parcela", "a conta") always reaches the pick, never commitment_not_found while active commitments exist; "parcela" narrows the pool to installments (WA-CAP-15b, fixed 2026-07-11). The pick posts a payment linked to the chosen occurrence, reply "✅ <nome> paga: R$ … (<mês>)." Direct form skips the ask (commitment_paid/commitment_paid_simple).

**Variants:**
- Explicit month (`paguei a parcela do sofá de agosto`, WA-CAP-15c/d): the stated month is targeted, not the current one. A FUTURE month first confirms the value — "*Sofá* de agosto de 2026: a parcela é R$ 280,00. Confirma esse valor? Pode responder *sim* ou mandar o valor pago." — `sim`/`confirmo` pays the parcel value; a number pays that value when plausible (±20% for a ≤1-month-out parcel, ±50% farther — early-payoff discounts), otherwise pay_confirm_doubt asks once ("responde *confirmo* — ou manda o valor certo"), and `confirmo` then pays the doubted value.
- `paguei a última parcela do sofá` (WA-CAP-15e): targets the plan's final month via the same confirmation flow.
- Payoff celebration (WA-CAP-15f/g, 2026-07-11): when the payment closes the LAST open parcel — every parcel accounted for, not just the positionally-last month — the reply is "🎉 *Sofá* quitado! Última parcela paga: R$ … (<mês>). Foram N parcelas. 💙" instead of "Faltam 0 de N". Paying the final month while an earlier parcel is still open does NOT celebrate.
- Advance-payment discount (2026-07-11): confirming a future parcel BELOW its expected value appends a footer line to the SAME message — "👏 Mandou bem! Pagando adiantado você economizou R$ <expected − paid>." Paying exactly the parcel value (`sim`) gets no note.
- "Faltam N de M" counts parcels actually UNPAID (`count − paid_count`, presumed + posted), never the positional parcel number — an advanced última reads "Faltam 34 de 36", not "Faltam 0 de 36" (fixed 2026-07-11).
- Already paid this month → "<nome> já está paga em <mês> 👍 Nada a fazer."
- Card subscription (Netflix on card) → commitment_on_bill "entra direto na fatura… não precisa marcar. 😉" — also guarded on the numbered-pick path now (picking a card commitment never creates a payment row; latent bug fixed 2026-07-11).
- No match (a NAMED commitment that doesn't exist) → commitment_not_found.

Pins: `app/services/whatsapp/pay_commitment_decider.rb:1`, `app/services/whatsapp/reply_router.rb:120-200`, `config/locales/pt-BR.yml:1374-1381`

### WA-CAP-16 — Correction: "na verdade foi 54,90" edits the last WA row in place

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Marina: `padaria 45 no débito no itaú` (creates a WA-posted row ≤24h old).
2. From the same chat: `na verdade foi 54,90`.

**Expect:** The SAME transaction row updates to 5490 centavos (row count unchanged), reply "✅ Corrigido: R$ 54,90 em Itaú (Marina)."

**Variants:**
- WA-CAP-18 too old: age the row, then send the correction → "Não achei um lançamento recente pra corrigir."; row untouched.
```
bin/rails runner 'User.find_by!(email_address:"marina@azulzin.dev").account.transactions.where.not(whatsapp_message_id: nil).order(created_at: :desc).first.update_columns(created_at: 25.hours.ago)'
```
- Unclear correction (`tava errado aquilo`) → edit_unclear "Não entendi a correção. Me diz assim: 'na verdade foi 54,90' — ou ajusta no app."

Pins: `app/services/whatsapp/edit_last_handler.rb:13-46`, `config/locales/pt-BR.yml:1380-1382`

### WA-CAP-17 — Category correction: "muda pra mercado" flips category_source to user and feeds memory

Seed: `dev:seed_demo` · AI: live-AI

**Steps:**
1. From Marina: `pão de queijo 12 no débito no itaú` (fresh WA-posted row; Mercado exists in the account's closed set).
2. From the same chat: `muda pra mercado`.
3. Capture the same merchant again: `pão de queijo 15 no débito no itaú`.

**Expect:** Step 2: row's category = Mercado, `category_source` = 'user' (check hub or runner), reply edited. Step 3: auto-categorized Mercado via merchant memory — reply appends "· Mercado" (posted_account_categorized). This is the human-signal → memory chain.

**Variants:**
- Category label outside the account's set (`muda pra alquimia`) → Categories::Resolve returns nil → edit_unclear, row untouched.

Pins: `app/services/whatsapp/edit_last_handler.rb:67-71`, `app/services/whatsapp/decider.rb:91-92`

### WA-CAP-19 — Undo: "apaga o último" reverses the last WA row (zero-LLM regex pre-pass)

Seed: `dev:seed_demo` · AI: deterministic (needs a live key only to create the row first)

**Steps:**
1. Post a WA row first (e.g. `padaria 54,90 no débito no itaú`).
2. From Marina: `apaga o último`. Watch the log: NO extraction call.
3. Also verify `desfaz`, `errei`, `foi engano` all match the frozen regex.

**Expect:** Row reversed/removed, balance restored to the exact prior centavos, reply "🗑️ Desfeito: R$ 54,90 em <merchant>." Row disappears from the browser ledger on refresh (HYB-04).

**Variants:**
- WA-CAP-20 nothing to undo (fresh user / all rows >24h) → "Não achei nada recente pra desfazer."; no mutation.
- Undo isolation in the couple: Marina's `apaga o último` must reverse HER last row, never Rafael's more recent one (`last_wa_row` scopes created_by) — post from both phones, undo from Marina, verify Rafael's row survives.

Pins: `app/services/whatsapp/interpreter.rb:9,32`, `app/services/whatsapp/undo_handler.rb:13-34`, `config/locales/pt-BR.yml:1383-1385`

### WA-EXP-02 — Partner phone capture: shared account, per-member attribution (WA view of MU-09, §6)

Seed: `dev:seed_demo` · AI: live-AI

Marina AND Rafael are verified on separate JIDs into the ONE "Andrade" account (both prefilled in the simulator). Catalog note: WA-GOAL-07 covers member attribution for goals; this generalizes it to capture — no dedicated WA-CAP id exists.

**Steps:**
1. From Rafael's chat (`5511976543210@c.us`): `farmácia 25,90 no débito no nubank`.
2. From Marina's chat: `apaga o último`.
3. Log in as marina@azulzin.dev and check the row's attribution in the web hub.

**Expect:** Row posts into the SHARED account with created_by = Rafael (both see it in the hub). Marina's undo must NOT touch Rafael's row (her `last_wa_row` is scoped to her): she gets "Não achei nada recente pra desfazer." unless she has her own fresh row.

**Variants:**
- Rafael corrects Marina's row: his `na verdade foi 20` must edit HIS last row only, never hers.
- Clean-room couple: `exploratory:seed[3]` gives owner test-3 + partner test-3b both WA-verified (seed prints the JIDs) if you want this on a fresh account instead of demo.

Pins: `app/services/whatsapp/decider.rb:80-81,109-115`, `lib/demo_seed.rb:62-63`

### WA-CAP-21 — Audio PTT auto-commit: spoken expense via real Groq STT

Seed: `dev:seed_demo` · AI: live-AI (GROQ_API_KEY for STT + OPENROUTER key for extraction; browser mic access on :3001)

**Steps:**
1. In Marina's chat click the 🎙 button and speak: "mercado, cinquenta e quatro e noventa, no débito no Itaú" — the simulator records and injects it as ptt (audio/wav).
2. Check the transcript: `bin/rails runner 'puts WhatsappMessage.order(:id).last.transcription'`

**Expect:** `msg.transcription` stored; the finance-vocab Whisper prompt biases digit money; extraction posts 5490 centavos with the normal ✅ reply. The por-extenso→digits normalization is prompt-only — exploratory: try "mil e duzentos" (→ 120000 centavos expected).

**Variants:**
- WA-CAP-32 silence: record ~3s of silence → if Whisper returns an empty transcript, reply "Não consegui ouvir seu áudio 😕 Pode mandar de novo?", message failed (stt_empty), NO LLM call.
- WA-CAP-32b prompt-echo hallucination (measured live 2026-07-11): a ~1s noise clip made Whisper echo the vocab-bias prompt back as a confident expense ("Gastei R$ 200 na caixinha da poupança", no_speech_prob=0) — and it posted R$ 200. Now: a transcript that is a near-duplicate (Levenshtein ≤25%) of any prompt sentence is treated as no-speech → same reply as WA-CAP-32, message failed (stt_echo), raw hallucination kept in `transcription` for tuning. Exploratory: send noise/silence clips of varied lengths — expect the 😕 reply, never a posted row.
- Ambient noise / mumbled amount → whatever the transcript yields rides the text pipeline; verify it parks rather than posting a wrong amount.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:105-121`, `app/services/whatsapp/stt_client.rb` (`prompt_echo?`), `config/openrouter.yml:21`

### WA-CAP-23 — Image receipt reconciles to an existing posted row: no duplicate, comprovante attached

Seed: `dev:seed_demo` · AI: live-AI (vision)

You need a receipt photo whose printed TOTAL you know exactly (e.g. a real cupom for 84,90).

**Steps:**
1. Capture by text first so a receipt-less posted row exists on a matched instrument: `mercado 84,90 no débito no itaú`.
2. In the same chat attach the receipt photo (📎) WITH caption `itaú` (a purchase receipt prints no origin, so the caption is the deterministic instrument hint).
3. Open the transaction in the web hub and confirm the attached receipt.

**Expect:** NO new row — reply "📎 Esse gasto já estava lançado: R$ 84,90 na conta Itaú (Marina). Anexei o comprovante."; the existing row now has the receipt blob. Reconcile matches exact amount + ±3 days + a receipt-less row, runs BEFORE the confidence gate (a timid vision read of a receipt that matches a posted row still reconciles, never parks a duplicate — widened 2026-07-11, WA-CAP-23b).

**Variants:**
- No caption / no instrument match (a plain recibo names no bank): reconcile searches ACCOUNT-WIDE and merges when the match is unique — e.g. a recibo for the exact value of a parcel payment posted this week attaches to that payment (WA-CAP-23b). With TWO equally-matching rows it refuses and parks — merging would be a guess (WA-CAP-23c).
- Same receipt sent twice as two separate messages (WA-CAP-36, 2026-07-11): the first send reconciled/posted, so the row carries a receipt and can't merge again — the second now ASKS "🤔 Opa, já tem um lançamento igual hoje: R$ … — <label>. É um gasto novo? …" — *sim* posts it anyway, *não* discards. Same guard for TEXT: an identical amount+merchant capture on the same day asks first (WA-CAP-35/35b).

Pins: `app/services/whatsapp/decider.rb:138-153`, `app/jobs/process_inbound_whatsapp_job.rb:85-95,138-143`, `config/locales/pt-BR.yml:1351-1352`

### WA-CAP-24 — Image receipt matching nothing posts a new transaction with receipt attached

Seed: `dev:seed_demo` · AI: live-AI (vision)

**Steps:**
1. Attach a clear receipt/Pix-comprovante photo in Marina's chat (no prior text capture; must not match any ledger row).

**Expect:** Confidence posture decides: crisp printed total → posts (unassigned unless origin_phrase/caption matches an instrument) with the receipt blob attached and a ✅ reply; blurry/unreadable total → deterministic cap ≤0.50 → parks with "Recebi 👍 Deixei pendente…". Pix comprovante: origin institution phrase should route the instrument. Exploratory: try cupom fiscal, maquininha slip, bank-app screenshot — the widened prompt accepts any completed-payment evidence.

**Variants:**
- Unreadable printed date on the receipt caps confidence at 0.60 → parks rather than posting with a guessed date.
- Boleto NOT yet paid / orçamento / product page screenshot → is_receipt=false → not_receipt flow (WA-CAP-33).

Pins: `app/services/whatsapp/receipt_extractor.rb:59-98,115-122`, `app/jobs/process_inbound_whatsapp_job.rb:85-95`

### WA-CAP-33 — Non-receipt image: honest reply, no ask-trap; caption rides the text pipeline

Seed: `dev:seed_demo` · AI: live-AI (vision)

**Steps:**
1. Attach any non-payment photo (a pet, a landscape) with NO caption.
2. Send `oi` afterwards and confirm it's treated as a fresh message (not swallowed as a slot answer).
3. Repeat WITH caption `mercado 84,90 no débito no itaú` (WA-CAP-34).

**Expect:** No caption: reply "Não consegui ler um comprovante aí 🤔 Pode mandar a foto do comprovante ou escrever o gasto? Ex.: \"mercado 84,90 no débito\"" — NO transaction, NO open ask. With caption: the caption posts 8490 centavos through the full text pipeline with the normal ✅ reply.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:127-133`, `config/locales/pt-BR.yml:1358`

### WA-EXP-01 — PDF receipt (document): rasterized to PNG page 1, then the receipt pipeline

Seed: `dev:seed_demo` · AI: live-AI (vision; Ghostscript required locally for Imports::PdfRasterizer)

The simulator's file picker accepts PDFs directly (📎 → pick the file; it goes out as a `document`). The curl injection below remains as the scriptable alternative. Use a real Pix comprovante exported as PDF.

**Steps:**
1. Encode: `base64 -i comprovante.pdf | tr -d '\n' > /tmp/b64.txt`
2. Inject:
```
curl -s localhost:3001/_inject -H 'Content-Type: application/json' -d "{\"jid\":\"5511987654321@c.us\",\"type\":\"document\",\"body\":\"\",\"media\":{\"data\":\"$(cat /tmp/b64.txt)\",\"mimetype\":\"application/pdf\",\"filename\":\"comprovante.pdf\"}}"
```

**Expect:** PDF rasterized to PNG (page 1 only) → vision extraction → posts/parks exactly like an image receipt, receipt blob attached. Audit note: this path is unit-owned, not E2E'd — prime exploratory territory.

**Variants:**
- Corrupt/passworded PDF (no readable pages) → Imports::ParseError → treated as not_receipt: honest "Não consegui ler um comprovante aí 🤔…" reply, never a dead job. Test with `echo 'not a pdf' > fake.pdf` base64-injected.

Pins: `app/services/whatsapp/receipt_extractor.rb:133-140,73-77`, `app/controllers/api/whatsapp/webhooks_controller.rb:109-116`

### WA-CAP-22 — STT failure degrades: Groq down/unauthorized never dead-ends silently

Seed: `dev:seed_demo` · AI: broken-key

**Steps:**
1. Restart the stack WITHOUT the STT key (and no groq credentials) — `SttClient` raises "missing Groq API key" as `SttClient::Error`. (Alternatively `GROQ_API_KEY=broken bin/dev-fake`.)
2. Send any voice note from Marina's chat.
3. Watch the Rails log for the retries.

**Expect:** Job retries 3× (5s waits), then fail_and_tell: message status 'failed' with error 'stt_failed: …' set FIRST, then reply "Não consegui ouvir seu áudio 😕 Pode mandar de novo?" No transaction, no half-written row, message never stuck at 'processing'.

**Variants:**
- Transport flavor: point ENDPOINT at a black-holed host (or drop network) — timeouts are wrapped into `SttClient::Error` (stt_client.rb:28-33) so the SAME degrade fires, not a silent dead-end.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:27-38`, `app/services/whatsapp/stt_client.rb:22-33`

### WA-CAP-30 — Extraction/vision AI failure degrades: fail-and-tell, never silence

Seed: `dev:seed_demo` · AI: broken-key

**Steps:**
1. Restart with `OPENROUTER_API_KEY=invalid-key bin/dev-fake` (401 → Unauthorized < Error) or unset it entirely.
2. From Marina: `mercado 54,90` (text).
3. Repeat with an image receipt to prove the vision path degrades identically.

**Expect:** 3 retry attempts in the log, then message status 'failed' (error 'ai_failed: …') and reply "Tive um problema aqui e não consegui processar sua mensagem 😕 Pode tentar de novo daqui a pouco?" NO transaction. The mark-failed-then-reply order means even a sidecar hiccup can't re-strand the message.

**Variants:**
- Rate-limit flavor (429) gets polynomial backoff before the same degrade — only observable against the real API under pressure; exploratory.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:15-23,33-38`, `app/services/open_router_client.rb:59,85-88`, `config/locales/pt-BR.yml:1359`

### WA-CAP-31 — Media-typed message with no attached media: resend ask, no AI call

Seed: `dev:seed_demo` · AI: deterministic (works without any AI key)

Simulates a sidecar download failure: an image envelope with NO media key.

**Steps:**
1. Run:
```
curl -s localhost:3001/_inject -H 'Content-Type: application/json' -d '{"jid":"5511987654321@c.us","type":"image","body":""}'
```
2. Watch the chat and the Rails log.

**Expect:** Reply "Não consegui receber o que você mandou 😕 Pode enviar de novo?"; message failed (media_missing); NO AI call in the log; no transaction.

**Variants:**
- Unsupported media type (exploratory): inject type 'video' WITH media — `map_type` falls through to 'text' (webhooks_controller.rb:109-116), so the media guard is skipped and an empty body rides the text extractor → expect the help reply. Flag as a gap if the reply reads as a non-sequitur after sending a video.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:56-59`, `config/locales/pt-BR.yml:1357`

### WA-CAP-25 — Per-minute flood cap: 21st message in a minute is silently stored as failed

Seed: `dev:seed_demo` · AI: live-AI — WARNING: the first 20 messages each fire a REAL OpenRouter call; keep bodies short/cheap

**Steps:**
1. Run:
```
for i in $(seq 1 21); do curl -s localhost:3001/_inject -H 'Content-Type: application/json' -d "{\"jid\":\"5511987654321@c.us\",\"body\":\"cafe $i,50 na loja $i\"}" >/dev/null; done
```
2. Count replies in the chat and check the last message's status via runner.

**Expect:** 20 messages processed (each replied); the 21st is stored but marked failed/rate_limited with NO reply and NO AI call — this SILENCE is the pinned real behavior (the catalog's 'golden rate-cap reply' was superseded; E2E asserts exactly 20 replies). Exploratory judgment call: does silent drop feel right at the 21st message? Bodies must VARY (amount or merchant): identical bodies trip the duplicate-confirmation ask (WA-CAP-35) at message 2, which is its own correct behavior but not what this scenario measures.

**Variants:**
- Wait 61s and send message 22 → processed normally (window is rolling 1 minute).

Pins: `app/jobs/process_inbound_whatsapp_job.rb:42,51-53`, `test/e2e/whatsapp/capture_test.rb:320-337`

---

Session wrap-up: `bin/rails whatsapp:capture_stats` prints the per-modality posted/parked/asked readout + correction rates for the run.
## 3. Goals — creation, checks, replan, celebrate

This chapter exercises the whole Goals subsystem: the WhatsApp goal-creation chat and the web draft→plan-cards flow, the weekly checker with its pace bands and anti-nag gates, the predictive warnings (missed_month / red_month / budget_raised), Reorganizar (WA + web), budget cuts, speed-up contributions, and the one-shot celebration. It uses seeds 6, 7, 8, 9, 10 and 15 — run `bin/rails "exploratory:seed[N]"` per scenario — plus `dev:seed_demo` for the couple/history-dependent cases.

Conventions used throughout:

- Stack up: `bin/dev-fake` (Rails :3000, WA simulator :3001). In dev NOTHING recurring fires — kick every sweep manually with the exact runner given per scenario.
- Seed users: `test-N@azulzin.dev` / `test1234`; owner JID `5511910000NNN`-style (`exploratory:seed[10]` → `5511910000010@c.us` — the seed prints the exact JID). Re-running a seed wipes and recreates the account, which is also the cheapest way to reset burnt weekly guards/delta-gates.
- WA outbound notifications need per-user prefs. One-liner (adapt the email): `bin/rails runner 'User.find_by!(email_address:"test-7@azulzin.dev").notification_prefs.update!(whatsapp_consent: true, goal_alerts: true, wa_intro_sent_at: Time.current)'` — and test inside 08–21 America/Sao_Paulo. The in-app Notification row is the reliable observable regardless (dashboard alert banner, or `bin/rails runner 'puts Notification.where(user: User.find_by!(email_address:"test-7@azulzin.dev")).pluck(:kind)'`); the WA bubble is the bonus.
- Only the WA *trigger* message ("quero criar uma meta") needs a live AI key; every subsequent chat reply, "reorganizar", and the entire weekly check are zero-LLM. Pace math is date-of-run dependent — always calibrate against `Goals::Progress.new(g).expected_cents` in console, never hardcode, and run checker scenarios on a day AFTER the household's payday (expected MTD is 0 before it).

---

**Creation — WhatsApp chat**

### WA-GOAL-01 — WA chat full happy path: trigger → Q&A → offer → ACTIVE goal + savings commitment

Seed: `exploratory:seed[10]` · AI: live-AI (trigger message only)

**Steps:**
1. `bin/rails "exploratory:seed[10]"`, start `bin/dev-fake`, open http://localhost:3001 and pick the seed-printed owner JID (`5511910000010@c.us`).
2. Type: `quero criar uma meta`
3. Reply in sequence, waiting for each question: `1` (comprar algo) → `Carro novo` → `20.000` → `dezembro de 2027` → `2.000`
4. At the offer, reply: `sim`
5. Web check: log in as `test-10@azulzin.dev` / `test1234`, open `/goals` and the Compromissos list.

**Expect:**
- Each slot question in order: `goal_flow.ask_kind` → `ask_name` → `ask_amount_purchase` → `ask_month` → `ask_initial_saved`.
- The offer renders `goal_flow.offer` with the monthly amount in whole reais (CEIL), a "reaches" line, and a cuts block.
- `sim` replies `goal_flow.activated`: "💙 Meta *Carro novo* ativada! Guardar R$ X/mês a partir de <mês> — te lembro todo mês." (If the account has more than one non-savings account, a numbered source pick appears before activation — see GL-EXP-01.)
- `/goals` shows the goal ACTIVE: target R$ 20.000,00, já guardado R$ 2.000,00. Compromissos shows a kind `savings` commitment debiting the checking source into the Caixinha. The goal conversation is closed.

**Variants:**
- Garbage amount (`vinte mil paus`) → `goal_flow.reask_amount`, slot re-asked, TTL refreshed.
- Garbage month (`sei lá`) → `goal_flow.reask_month`.
- Initial ≥ target (`25.000` at the já-guardado slot) → `goal_flow.reask_initial_saved_high`, value dropped.
- `talvez` at the offer → `goal_flow.offer_reprompt` (only sim/não move the state).

Pins: `app/services/whatsapp/goal_flow_handler.rb:15-32`, `app/services/whatsapp/goal_flow_router.rb:78-133`, `app/services/whatsapp/goal_flow_router.rb:300-357`, `app/services/goals/activate.rb:25-48`, `test/e2e/whatsapp/goals_chat_test.rb:8-36`

### GL-EXP-01 — WA chat: numbered caixinha & source picks

Seed: `dev:seed_demo` · AI: live-AI (trigger only)

**Steps:**
1. `bin/rails dev:seed_demo`; log in as `marina@azulzin.dev` / `demo1234` and create a SECOND savings account "Caixinha Viagem" (kind poupança) at `/bank_accounts`. (≥2 non-savings accounts already exist: Itaú + Nubank.)
2. In the simulator as `5511987654321@c.us`, walk WA-GOAL-01's chat to the offer and reply `sim`.
3. A numbered caixinha list appears — reply `2`.
4. A numbered source list appears — reply `1`.

**Expect:**
- `goal_flow.ask_caixinha_pick` with numbered options in created_at order; then `goal_flow.ask_source_pick` excluding the picked caixinha; then `goal_flow.activated`.
- The goal links the picked caixinha (`bank_account_id`) and the commitment debits the picked source.

**Variants:**
- Reply `9` (out of range) or free text at a pick → the same numbered prompt is re-asked.
- Double `sim` sent twice fast → guarded transition: activation runs exactly once, exactly one commitment.

Pins: `app/services/whatsapp/goal_flow_router.rb:300-334`, `config/locales/pt-BR.yml:1425-1426`

### WA-GOAL-02 — "não" at the offer discards the invisible draft (quota hygiene)

Seed: `exploratory:seed[10]` · AI: live-AI (trigger only)

**Steps:**
1. Walk WA-GOAL-01's chat to the offer. Verify a draft exists: `bin/rails runner 'puts User.find_by!(email_address:"test-10@azulzin.dev").account.goals.count'` → 1, status draft.
2. Reply: `não`
3. Re-run the count from step 1.

**Expect:**
- Reply is exactly `whatsapp.replies.goal_flow.discarded`: "Tranquilo, descartei. Quando quiser, é só falar comigo — ou montar no app. 💙"
- Draft Goal DESTROYED (count back to 0 — it must not linger and burn the ≤5/month AI-session quota); conversation closed.

**Variants:**
- WA-GOAL-02b: `cancelar` mid-collection (right after `1`) → `goal_flow.cancelled`, conversation closed, no draft was ever created.
- `parar` / `esquece` / `deixa` also match CANCEL_RE.

Pins: `app/services/whatsapp/goal_flow_router.rb:292-296`, `test/e2e/whatsapp/goals_chat_test.rb:39-49`

### WA-GOAL-03 — 24h TTL expiry: a dead chat stops swallowing messages

Seed: `exploratory:seed[10]` · AI: live-AI (trigger + the expense extraction)

**Steps:**
1. Start the chat (`quero criar uma meta`) and answer `1`.
2. Expire the conversation manually:
```
bin/rails runner 'GoalConversation.where.not(status: "closed").update_all(expires_at: 1.minute.ago)'
```
3. Type in the simulator: `padaria 54,90`
4. Then type: `quero criar uma meta`

**Expect:**
- Step 3 flows through the NORMAL capture pipeline — expense posted, capture reply naming R$ 54,90 — NOT consumed as the goal-name slot.
- Step 4 starts a FRESH chat, and the lazy janitor destroys any stale draft (quota released).

Pins: `app/models/goal_conversation.rb:10,26-31`, `app/services/whatsapp/goal_flow_handler.rb:27-32`, `test/e2e/whatsapp/goals_chat_test.rb:64-78`

### WA-GOAL-04 — expense-looking text mid-chat is a slot answer, never an expense

Seed: `exploratory:seed[10]` · AI: live-AI (trigger only; everything after is zero-LLM)

**Steps:**
1. Start the chat and answer `1` (you are now at the NAME slot).
2. Type: `mercado 54,90`
3. Check `/transactions` as `test-10@azulzin.dev`.

**Expect:**
- The text becomes the goal's NAME ("mercado 54,90" — the conversation wins) and the chat asks the next slot (amount).
- NO transaction is created from WhatsApp while the chat is open.

Pins: `app/services/whatsapp/goal_flow_router.rb:36-43,109-113`, `test/e2e/whatsapp/goals_chat_test.rb:81-92`

### WA-GOAL-06 — at MAX_ACTIVE=5 the trigger refuses before asking anything

Seed: `exploratory:seed[10]` · AI: live-AI (trigger only)

**Steps:**
1. Create 5 active goals in console:
```
bin/rails runner 'u=User.find_by!(email_address:"test-10@azulzin.dev"); 5.times { |i| u.account.goals.create!(kind: "savings_rate", name: "Meta #{i}", target_cents: 100_000*(i+1), status: "active", created_by: u) }'
```
2. In the simulator type: `quero criar mais uma meta`

**Expect:**
- Exact reply `whatsapp.replies.goal_flow.limit_reached`: "Vocês já têm 5 metas ativas. Concluir ou abandonar uma no app abre espaço pra próxima. 💙"
- No conversation opened; still exactly 5 goals.

**Variants:**
- Same cap on web (WEB-GOAL-08): `/goals/new` redirects to `/goals` with flash `t('goals.new.limit_reached')`.

Pins: `app/services/whatsapp/goal_flow_handler.rb:16`, `app/models/goal.rb:15,69-72`, `test/e2e/whatsapp/goals_chat_test.rb:95-107`

### WEB-GOAL-02 — infeasible deadline → ONE honest counter-offer; "sim" applies it; zero capacity → too_tight

Seed: `exploratory:seed[10]` · AI: live-AI (trigger only)

**Steps:**
1. Chat: `quero criar uma meta` → `1` → `Apartamento` → `100.000` → month = next month (e.g. `agosto`).
2. At the counter-offer, reply `sim`.
3. too_tight probe: re-seed, then remove essentially all disposable income (add a big fixed commitment close to the monthly income via the Compromissos page) and repeat step 1.

**Expect:**
- Counter renders `goal_flow.counter_offer_date`: "Essa meta não fecha no prazo que você pediu. Com R$ X/mês você chega em <mês> — quer seguir assim?" with a FLOOR whole-reais amount.
- `sim` applies the feasible date to the draft and re-presents the now-feasible offer — one round-trip, the user never restates a number.
- too_tight: draft destroyed, chat closed, `goal_flow.too_tight` copy.

**Variants:**
- savings_rate total ≤ current guardado → `goal_flow.below_current_guardado` re-asks the amount naming today's guardado (floor).
- `não` on the counter → draft discarded (`goal_flow.discarded`).

Pins: `app/services/whatsapp/goal_flow_router.rb:242-267,281-290`, `config/locales/pt-BR.yml:1421-1424`

### GL-EXP-02 — no caixinha at accept → friendly block, draft destroyed

Seed: `exploratory:seed[10]` · AI: live-AI (trigger only)

**Steps:**
1. Walk the chat to the offer (WA-GOAL-01 steps 2–3).
2. Before replying, remove the Caixinha at `/bank_accounts` (soft delete) so the account has no savings-kind bank account. (If the app refuses to remove it, use a fresh registered user with only one checking account, WA-verified via the web code flow — the condition is simply "no savings account, or no distinct source".)
3. Reply: `sim`

**Expect:**
- `goal_flow.no_caixinha`: "Pra ativar uma meta você precisa de uma conta poupança e uma conta de origem. Cria a poupança no app e me chama de novo. 💙"
- Draft destroyed, chat closed — the always-linked activation contract (round-3 decision 4).

Pins: `app/services/whatsapp/goal_flow_router.rb:300-302,359-363`, `config/locales/pt-BR.yml:1428`

### WA-GOAL-07 — member (not owner) creates a goal via WA: account-scoped, attributed to the member

Seed: `dev:seed_demo` · AI: live-AI (trigger only)

**Steps:**
1. `bin/rails dev:seed_demo`; in the simulator switch to Rafael's JID `5511976543210@c.us`.
2. Run the full chat: `quero criar uma meta` → `1` → `Viagem` → `10.000` → `dezembro` → `não` → `sim`.
3. Log in as `marina@azulzin.dev` and open `/goals`.

**Expect:**
- The goal lives on the SHARED account (visible to Marina), `created_by` = Rafael; the savings commitment also carries Rafael's attribution. Both members see it identically.

Pins: `test/e2e/whatsapp/goals_chat_test.rb:144-165`, `app/services/goals/activate.rb:20-22,71-78`

---

**Creation — web**

### WEB-GOAL-01 — web create: draft → 3 plan cards (leve/recomendado/acelerado) → choose → ACTIVE + commitment with ends_on

Seed: `exploratory:seed[10]` · AI: deterministic (plan numbers; NarrativeJob polishes coach notes asynchronously IF a key is set, fail-open to template notes)

**Steps:**
1. `bin/rails "exploratory:seed[10]"`; log in `test-10@azulzin.dev` / `test1234`.
2. Visit `/goals/new` → kind "comprar algo", name `Carro novo`, valor `R$ 20.000,00`, data dez/2027, já guardado `R$ 2.000,00` + pick where it sits → Criar.
3. On the draft page pick **recomendado**, choose caixinha + source account, activate.
4. Open the goal show page.

**Expect:**
- Draft page renders 3 plan cards with exact monthly cents recomputed from the frozen baseline — tampering the POSTed plan numbers is ignored (server recomputes via `Goals::Recompute`).
- After choose: redirect with `t('goals.choose.activated')` notice; status ACTIVE; `starts_on` = next month; savings commitment created with amount = the chosen plan's monthly, `ends_on = starts_on >> (⌈(target−initial)/monthly⌉−1)`, `schedule_day` = earliest payday.
- Goal show page renders a "começa em <mês>" pre-start note instead of "esperado R$ 0".

**Variants:**
- Refresh the draft page after adding a new income → plans re-scored in-request (`analyze!` on every draft view).
- Choose without picking a source, or source == caixinha → alert `t('goals.choose.errors.missing_caixinha')`.

Pins: `app/controllers/goals_controller.rb:21-35,99-110`, `app/services/goals/activate.rb:25-95`, `app/views/goals/draft.html.erb`

### WEB-GOAL-03 — draft orçamento sliders (caps) re-render plans via Turbo; clamped; reset clears

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. As Marina, create a web draft (WEB-GOAL-01 steps 1–2 shape) and STOP on the draft page — demo history provides flexible categories with `trimmable_median_cents > 0` (Lazer/Restaurantes-style).
2. Drag a category slider down and submit the caps form.
3. Use "reset".

**Expect:**
- Only the plan area Turbo-swaps (sliders keep their DOM position); plan monthly/cuts change consistently.
- Caps are clamped to `[median − trimmable, median]`; a cap equal to the median is dropped (no-op); reset clears `user_caps` entirely. Out-of-clamp values are clamped server-side; unknown category ids ignored.

**Variants:**
- POST caps on a non-draft goal → 303 redirect to the goal page, nothing written.

Pins: `app/controllers/goals_controller.rb:114-122,178-189`, `app/views/goals/caps.turbo_stream.erb`

### WEB-GOAL-09 — web create validation set: each named error renders on the form

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. At `/goals/new` submit each bad combo in turn:
   a. initial `R$ 25.000,00` ≥ target `R$ 20.000,00`;
   b. initial `R$ 2.000,00` but no "Em qual poupança está?" account picked;
   c. kind "guardar mais" with total ≤ the shown current guardado;
   d. blank name.

**Expect:**
- (a) activerecord error `:exceeds_target` on `initial_saved_cents`; (b) `:blank` on `initial_saved_bank_account` (required because a savings caixinha exists); (c) `:below_current_guardado` on target, naming today's guardado in floor whole reais; (d) name presence.
- All render 422 on the form, in pt-BR, no goal created.

**Variants:**
- savings_rate submission silently drops the target_date/initial fields the browser always posts (`create_params` normalization) — verify no absence-validation error appears.

Pins: `app/models/goal.rb:31-44,84-93`, `app/controllers/goals_controller.rb:25-27,171-173`

### WEB-GOAL-10 — AI session cap: ≤5 drafts/account/month get a narrative; the 6th is template-notes only; ≤3 narrative calls per draft

Seed: `exploratory:seed[10]` · AI: live-AI (+ broken-key variant)

**Steps:**
1. Create 5 goals this calendar month (5× `/goals/new` submissions; WA-created drafts count too). Verify:
```
bin/rails runner 'puts User.find_by!(email_address:"test-10@azulzin.dev").account.goals.where(created_at: Date.current.beginning_of_month..).count'
```
   → 5.
2. Create a 6th goal at `/goals/new`; wait a minute and reload its draft page.
3. On one of the first drafts, edit the target 3+ times (each update re-enqueues NarrativeJob); reload after each.

**Expect:**
- 6th draft: NarrativeJob never enqueued (fail-closed quota) — plan cards show only the deterministic TEMPLATE notes, never an error.
- Per-draft: after `ai_calls_count` reaches 3 the job returns before calling the LLM — further re-edits stop refreshing narratives.
- ClassifyJob still runs on every create (quota-exempt). The count is on existing rows — which is why declined WA drafts are destroyed (quota released).

**Variants:**
- Kill the key (`OPENROUTER_API_KEY=broken bin/dev-fake`) and create a draft → Narrator absorbs the failure, template notes stand, no visible error (fail-open).

Pins: `app/controllers/goals_controller.rb:29-30,92,148-152`, `app/services/goals.rb:15-16`, `app/jobs/goals/narrative_job.rb:14-21`

### WEB-GOAL-11 — guarded transitions: double-submit activate, bad template, stale replan

Seed: `exploratory:seed[10]` · AI: deterministic

**Steps:**
1. Create one web draft ready to choose; open the SAME draft in a second browser tab.
2. (a) Activate in tab 1, then activate with a DIFFERENT template in tab 2.
3. (b) Submit choose with a tampered template — edit the radio value to `banana` in devtools and submit the real form (a bare curl PATCH dies on CSRF first).
4. (c) On an active goal, edit the replan form's mode field to `banana` in devtools and submit.

**Expect:**
- (a) Tab 2 gets alert `t('goals.choose.errors.not_draft')`; exactly one commitment exists and the plan matches tab 1's template.
- (b) Alert `errors.invalid_template`. (c) Alert `t('goals.replan.errors.invalid_mode')`.
- Never a 500, never a second commitment.

**Variants:**
- Two concurrent activations of two different drafts while at 4 active goals → the account lock serializes; the loser gets `:too_many_active`.

Pins: `app/services/goals/activate.rb:29,42-43,53-59`, `app/services/goals/replan.rb:33-47`, `app/controllers/goals_controller.rb:58-67`

---

**Weekly checks & pace bands**

### NT-GL-01 — weekly check: pace 81–95% of expected → at_risk goal_alert with exact gap (golden)

Seed: `exploratory:seed[7]` · AI: deterministic (pure Postgres)

**Steps:**
1. `bin/rails "exploratory:seed[7]"` — active goal "Carro" backdated 2 months; the seed trims the newest contributions so guardado reads exactly 93% of TODAY's expected (inside the 81–95% band). Expected grows daily, so re-seed on the day you test.
2. Enable WA prefs for `test-7@azulzin.dev` (conventions one-liner).
3. Record the expected/actual pair:
```
bin/rails runner 'g=User.find_by!(email_address:"test-7@azulzin.dev").account.goals.find_by!(name:"Carro"); p=Goals::Progress.new(g); puts({expected: p.expected_cents, actual: p.actual_cents}.inspect)'
```
4. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- GoalCheck row status `at_risk` with findings `[pace]`; a `goal_alert` Notification row lands (dashboard banner / runner — there is no /notifications page).
- Simulator receives EXACTLY: "👀 Sua meta *Carro*: faltam R$ <gap> para o valor deste mês e o mês está acabando. Uma transferência para a poupança resolve. 💙" where gap = expected − actual in whole-reais CEIL (verify against step 3's numbers).
- Goal show page pace badge takes the "at risk" band color.

**Variants:**
- Calibrate total actual to 96% of expected — `g.update_columns(initial_saved_cents: g.initial_saved_cents + (e*96/100 - a))` using step 3's `e`/`a` — re-seed first, re-run → `on_track`, silent (the ≥95% boundary).
- Re-run the job the same day → idempotent: no second row, no second message (unique `[goal_id, period_start]` + `record!` period_key).

Pins: `app/services/goals/checker.rb:38-43,65-71`, `app/jobs/goals/notify_member_job.rb:82-94`, `config/locales/pt-BR.yml (goal_alert_pace)`, `test/e2e/notifications/goals_test.rb:11-27`

### NT-GL-02 — weekly check: pace ≤80% → off_track band

Seed: `exploratory:seed[8]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[8]"` — same goal but paid [1, 0.5, 0] = 50% of expected. Enable WA prefs for `test-8@azulzin.dev`.
2. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- GoalCheck status `off_track`; dashboard banner + WA pace message naming Carro; the goal page progress bar takes the off_track band class (`goal_bar_class`).
- Boundary: exactly 80.000% is still **at_risk** — the strict check is `actual*100 < expected*80`. Probe with total actual = `e*80/100 ± 1` cent (delta calibration as in NT-GL-01, re-seed between probes).

**Variants:**
- expected 0 and actual 0 (goal starts next month) → status `insufficient_data`, badge "sem dados", no alert.

Pins: `app/services/goals/checker.rb:65-71`, `app/services/goals.rb:19-20`, `test/e2e/notifications/goals_test.rb:30-39`

### NT-GL-11 — grace: a freshly activated goal stays silent for 14 days + the pre-start gap month

Seed: `exploratory:seed[10]` · AI: deterministic

**Steps:**
1. Activate a goal TODAY through the real web flow (WEB-GOAL-01) — `starts_on` = next month. Enable WA prefs for `test-10@azulzin.dev`.
2. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- No goal_alert row, no WA message — no findings before `max(activation+14d, starts_on)`. Goal page shows "começa em <mês>" instead of expected R$ 0.
- NOTE (deliberate, round-4 decision 6): RiskScan findings IGNORE this grace — a red_month can still fire on a brand-new goal.

Pins: `app/services/goals/checker.rb:30-35`, `app/services/goals.rb:21`, `test/e2e/notifications/goals_test.rb:42-50`

### NT-GL-03 — big commitment-less purchase within 7 days → big_purchase; 8 days ago → silent

Seed: `exploratory:seed[6]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[6]"` — goal "Carro" on-track ([1,1,1], no pace noise). Enable WA prefs for `test-6@azulzin.dev`.
2. Add one expense via web: `/transactions` → new expense `R$ 600,00`, category Outros, débito on a non-card account, occurred today. (R$ 600,00 = 60_000 cents clears the threshold `max(3× category baseline median, 20% × monthly parcel)`.)
3. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- goal_alert payload finding `big_purchase` with `amount_cents 60_000`; WA copy `goal_alert_big_purchase`: "⚠️ Vi uma compra grande de R$ 600 este mês. Sua meta *Carro* pode atrasar — quer ajustar no app?"

**Variants:**
- Edit the expense's `occurred_on` to 8 days ago → outside `BIG_PURCHASE_LOOKBACK_DAYS`, silent.
- An expense paid AS a commitment occurrence (has `commitment_id`) → never flagged.

Pins: `app/services/goals/checker.rb:46-57`, `app/services/goals.rb:22-24`, `test/e2e/notifications/goals_test.rb:131-156`

### NT-GL-04 — anti-nag delta-gate: same cause next week is silent; day-15 re-arm fires (NT-GL-06)

Seed: `exploratory:seed[7]` (chained after NT-GL-01) · AI: deterministic

**Steps:**
1. Run NT-GL-01 so the at_risk pace alert exists.
2. Simulate "next week" by shifting last week's artifacts back:
```
bin/rails runner 'wk=Date.current.beginning_of_week; GoalCheck.where(period_start: wk).update_all(period_start: wk-7); Notification.where(kind: "goal_alert", period_key: wk).update_all(period_key: wk-7, created_at: 7.days.ago, whatsapp_sent_at: 7.days.ago)'
```
3. Trigger (same pace shortfall still true):
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```
4. Re-arm probe: set the shifted notification's `created_at` to `15.days.ago` AND worsen the pace to 50% of expected (delta calibration on `initial_saved_cents` as in NT-GL-01, targeting `e*50/100`; `update_columns` skips validations). Re-run the trigger.

**Expect:**
- Step 3 is SILENT — same (finding, category, month) cause at the same severity: no new goal_alert row, no WA message.
- Step 4 FIRES — cooldown lifted (15 days) + worsening at_risk→off_track beats the delta-gate.

**Variants:**
- NT-GL-05: same worsening but `created_at` only `7.days.ago` (inside the 14-day cooldown) → still silent; only urgent leads bypass the cooldown — spec-corrected contract, pinned in `goals_test.rb:84-102`.

Pins: `app/jobs/goals/notify_member_job.rb:69-94,96-108,118-120`, `test/e2e/notifications/goals_test.rb:54-71`

### NT-GL-12 — low-income month suppresses the pace nag

Seed: `exploratory:seed[7]` (fresh re-seed) · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[7]"` (~93% pace — would fire). Enable WA prefs.
2. Raise the frozen baseline income above reality so this month's entradas fall under 70% of baseline:
```
bin/rails runner 'g=User.find_by!(email_address:"test-7@azulzin.dev").account.goals.find_by!(name:"Carro"); g.update_columns(baseline: g.baseline.merge("median_income_cents" => 5_000_000))'
```
3. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- SILENT — no goal_alert row, no WA. The irregular-income guard also blocks the pace arm of off_track (an at_risk/off_track check can never carry zero findings).
- big_purchase would still fire if present — only pace is income-guarded.

Pins: `app/services/goals/progress.rb:60-64`, `app/services/goals/checker.rb:38-39,63-67`, `test/e2e/notifications/goals_test.rb:246-258`

### NT-GL-09 — weekly WA guard: two slipping goals, same user → ONE push, TWO dashboard rows

Seed: `exploratory:seed[7]` (fresh re-seed) · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[7]"`; enable WA prefs. Seed 7's "Carro" is already at_risk.
2. Add a SECOND backdated goal with its OWN caixinha (sharing one would count each other's transfers), calibrated to 88%:
```
bin/rails runner 'u=User.find_by!(email_address:"test-7@azulzin.dev"); a=u.account; cx=a.bank_accounts.create!(institution: Institution.first, nickname: "Caixinha Moto", kind: "savings", created_by: u); src=a.bank_accounts.kept.where.not(kind: "savings").first; start=Date.current.beginning_of_month << 2; g=a.goals.create!(kind: "purchase", name: "Moto", target_cents: 2_000_000, target_date: Date.current.beginning_of_month >> 10, status: "active", monthly_target_cents: 100_000, starts_on: start, activated_at: start.in_time_zone, bank_account: cx, created_by: u, baseline: Goals::Analyzer.call(a).to_snapshot, plan: {"projected_done_on" => (Date.current.beginning_of_month >> 10).iso8601}); a.commitments.create!(kind: "savings", goal: g, bank_account: src, amount_cents: 100_000, name: "Moto", starts_on: start, schedule_day: 5, schedule_kind: "fixed_day", created_by: u); e=Goals::Progress.new(g).expected_cents; g.update_columns(initial_saved_cents: e*88/100); puts g.id'
```
3. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- Simulator shows exactly ONE goals message this week; TWO goal_alert Notification rows exist (check by runner — there is no /notifications page) (`record!` is unconditional — the dashboard always sees both). The second alert's `whatsapp_sent_at` is nil.

**Variants:**
- `goal_achieved` is EXEMPT from this guard (see WEB-GOAL-06).

Pins: `app/jobs/goals/notify_member_job.rb:92,110-116`, `test/e2e/notifications/goals_test.rb:202-216`

---

**Predictive warnings**

### NT-GL-07 — missed_month is urgent: bypasses the 14-day cooldown; empathy variant per cause

Seed: `dev:seed_demo` (bespoke backdated recipe) · AI: deterministic

**Steps:**
1. `bin/rails dev:seed_demo`; enable WA prefs for `marina@azulzin.dev` (conventions one-liner).
2. Build a slipped goal with the seeding recipe, sized target `6_000_000` / monthly `300_000`, `starts_on` 2 months ago, its OWN caixinha, savings commitment `300_000` — and set `plan.projected_done_on` ~2 months tighter than the honest pace (the promise the miss will slip).
3. Pay parcels via console `Commitments::MarkPaid`: month−2 in full (`300_000`); month−1 only `50_000` (gap `250_000` → "R$ 2.500"). Backdate each payment's `occurred_on` into its month.
4. Optionally arm the cooldown first with a pace alert (to prove the bypass).
5. Trigger, in the month AFTER the miss:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- Fires even inside the 14-day cooldown (urgent bypass — it never bypasses the delta-gate, weekly guard, or daily cap). Check status escalates to `off_track`.
- Plain golden:
```
👀 A meta *Carro* ficou R$ 2.500 abaixo do combinado no mês passado.
No ritmo atual, a conclusão passa de <old> para <new>.
Responda *reorganizar* para ajustar o plano.
```
- Cause forks (set the data, re-run on a fresh setup):
  - income: `g.update_columns(baseline: g.baseline.merge("median_income_cents" => 3_000_000))` so last month's entradas < 70% → opener "💙 A renda veio menor no mês passado — acontece, tá tudo bem."
  - essential: baseline categories include `{category_id: Moradia.id, name: "Moradia", flexibility: "essential", median_cents: X}` with last month's Moradia actual ≥ X + 5_000 → opener "💙 Moradia pesou R$ Y a mais... imprevistos acontecem, sem culpa."
  - plain: empty baseline categories + median_income 0.

**Variants:**
- A miss that does NOT slip the promised finish (caught-up / rounding-neutral) → silent (`scan_missed_month` requires projected > promised).
- savings_rate goal → never fires (purchase-only).

Pins: `app/services/goals/risk_scan.rb:90-139`, `app/jobs/goals/notify_member_job.rb:82-89`, `config/locales/pt-BR.yml (goal_alert_missed_month[_essential|_income|_plain])`, `test/e2e/notifications/goals_test.rb:108-127,274-295`

### NT-GL-08 — predictive findings coexist → FINDING_PRIORITY sends only the worst lead (red_month golden); the check records them all

Seed: `exploratory:seed[6]` · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[6]"` (on-track backdated goal, this month's parcel committed). Enable WA prefs.
2. red_month: add a `R$ 8.000,00` expense this month via `/transactions` so the month's remaining goes negative.
3. budget_raised: write an applied cut, then raise the standing budget above it:
```
bin/rails runner 'u=User.find_by!(email_address:"test-6@azulzin.dev"); a=u.account; g=a.goals.find_by!(name:"Carro"); l=a.categories.find_by!(name:"Lazer"); g.update!(plan: g.plan.merge("cuts" => [{"category_id" => l.id, "cap_cents" => 40_000}]), budgets_applied_at: Time.current)'
```
   then set Lazer's budget to `R$ 600,00` at `/categories`.
4. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```

**Expect:**
- ONE WA push, lead = red_month (priority: missed_month > red_month > next_month_red > budget_raised > pace > big_purchase):
```
⚠️ Este mês está fechando no vermelho: falta R$ <shortfall>, e a meta *Carro* pede R$ <parcela>.
Responda *reorganizar* para ajustar sem culpa. 💙
```
- `GoalCheck.findings` still records budget_raised too; status `off_track` (red current month).

**Variants:**
- budget_raised ALONE is non-urgent: inside a cooldown it stays dashboard-silent.
- next_month_red: instead of the cash expense, a big card purchase billing NEXT month → "👀 As faturas do cartão já somam R$ X no mês que vem..." copy.
- No goal parcel in the red month (commitment ended) → generic household trouble, NO goals alert (attribution rule).

Pins: `app/services/goals/risk_scan.rb:46-58,154-176`, `app/jobs/goals/notify_member_job.rb:23,59-67`, `test/e2e/notifications/goals_test.rb:161-182`

### NT-GL-13 — recently_replanned?: a goal replanned within a fortnight sits out the red-month scan

Seed: `exploratory:seed[6]` (fresh re-seed) · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[6]"`; enable WA prefs. Recreate NT-GL-08's red_month condition, but date the `R$ 8.000,00` expense to the 1st of this month (8+ days ago) so big_purchase can't fire and red_month is the only possible finding (seed 6 is on-track, so pace is silent).
2. Mark the plan as freshly replanned:
```
bin/rails runner 'g=User.find_by!(email_address:"test-6@azulzin.dev").account.goals.find_by!(name:"Carro"); g.update_columns(plan: g.plan.merge("replanned_on" => (Date.current - 10).iso8601))'
```
3. Trigger:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```
4. Change `replanned_on` to 15 days ago, clear the week's check rows (`GoalCheck.where(period_start: Date.current.beginning_of_week).delete_all` in a runner), and re-run the trigger.

**Expect:**
- Step 3 is SILENT (10 < GRACE_DAYS 14 — the fresh plan gets its quiet switch).
- Step 4 FIRES red_month.

Pins: `app/services/goals/risk_scan.rb:63-75`, `test/e2e/notifications/goals_test.rb:186-199`

---

**Reorganizar (replan) & budget cuts**

### WA-GOAL-05 — reorganizar via WA: keyword (zero LLM) → numbered offer → pick → plan rewritten, actual_cents invariant

Seed: `exploratory:seed[8]` · AI: deterministic (REPLAN_RE pre-pass, no key needed)

**Steps:**
1. `bin/rails "exploratory:seed[8]"` — genuinely slipped goal "Carro" (50% pace, real transfers into its caixinha).
2. Record the invariant BEFORE:
```
bin/rails runner 'puts Goals::Progress.new(User.find_by!(email_address:"test-8@azulzin.dev").account.goals.find_by!(name:"Carro")).actual_cents'
```
3. In the simulator (seed-printed JID) type: `reorganizar`
4. Reply: `1`
5. Re-run step 2 and inspect `/goals/:id` + Compromissos.

**Expect:**
- Offer shape (amounts derive from the seed — the guardado figure must equal step 2's value in floor whole reais):
```
💙 Meta *Carro*: você já guardou R$ <guardado>. Dá pra reorganizar assim:
1. Manter R$ <parcela>/mês — termina em <mês>
Responde o número, ou *não* pra deixar como está.
```
- Pick applies: "💙 Meta *Carro* reorganizada: R$ <parcela>/mês até <mês>. Sem culpa — o que importa é continuar."
- Invariants: `actual_cents` UNCHANGED; old commitment archived and a fresh one created at the new parcel; `starts_on` = next month and `activated_at` = now (grace restarts); `plan.replanned_on` = today; `budgets_applied_at` cleared (cuts reverted now, rewritten by the daily job when the new starts_on arrives); `initial_saved` rebased = old initial + last-month transfers, earmarked to the goal's caixinha.

**Variants:**
- `não` at the offer → `goal_replan.kept`, nothing changes.
- `banana` → `goal_replan.reprompt` with the same numbered options.
- No active purchase goal on the account → `reorganizar` answers `goal_replan.none`.
- Achieve the goal from console between offer and pick → `goal_replan.unavailable` (chat already closed — copy points to the app, not "try again").
- `reorganizar` MID-creation-chat with an active purchase goal → creation draft discarded, replan flow takes over; with NO active purchase goal → `goal_replan.none` and the half-built draft SURVIVES.

Pins: `app/services/whatsapp/interpreter.rb:13,33`, `app/services/whatsapp/goal_flow_router.rb:59-70,376-407`, `app/services/goals/replan.rb:32-116`, `test/e2e/whatsapp/goals_chat_test.rb:113-140`

### WEB-GOAL-05 — reorganizar via web: extend / hold_date from the goal page — same invariants

Seed: `exploratory:seed[8]` (fresh re-seed) · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[8]"`; log in `test-8@azulzin.dev`.
2. Visit `/goals/:id` — the `#replan` section lists the derived options → click "manter parcela" (extend). (hold_date only renders when it beats extend AND live capacity funds the higher parcel — visible mainly when the promised date is only a few months out.)

**Expect:**
- Redirect with `t('goals.replan.replanned')` notice naming the new monthly (whole reais) and month.
- The server RE-DERIVES the option — only the mode word crosses the wire; tampered numbers in the POST are ignored.
- The `#replan` section disappears afterwards (recently replanned goals have nothing to extend — `extend_option` gate).

**Variants:**
- On-plan goal → no `#replan` section at all (offer nil).
- Goal at target → offer nil (Achieve owns that moment).
- `mode=banana` via the tampered form → alert `errors.invalid_mode`.

Pins: `app/controllers/goals_controller.rb:58-67`, `app/services/goals/replan_offer.rb:26-76`, `app/services/goals/replan.rb:32-50`

### GL-EXP-03 — goal cuts: daily ApplyBudgetCutsJob writes plan cuts into standing budgets when starts_on arrives; min-tighten; idempotent

Seed: `exploratory:seed[9]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[9]"` — active goal caps Restaurantes at R$ 400,00 against a standing budget of R$ 600,00; log in `test-9@azulzin.dev`.
2. At `/categories` set Mercado's budget to `R$ 300,00` (the min-tighten probe: already tighter than the cap we'll add).
3. Add the Mercado cut and re-arm the cuts as pending (seed 9 pre-applied them and stamped `budgets_applied_at`, but the pack already raised Restaurantes back to R$ 600,00 — the runner's `budgets_applied_at: nil` re-arms them):
```
bin/rails runner 'u=User.find_by!(email_address:"test-9@azulzin.dev"); g=u.account.goals.where(status:"active").first; m=u.account.categories.find_by!(name:"Mercado"); g.update_columns(plan: g.plan.merge("cuts" => (g.plan["cuts"] || []) + [{"category_id" => m.id, "cap_cents" => 40_000}]), budgets_applied_at: nil)'
```
4. Trigger:
```
bin/rails runner 'Goals::ApplyBudgetCutsJob.perform_now'
```
5. Re-run the trigger.

**Expect:**
- `/categories`: Restaurantes budget now R$ 400,00 (trimmed); Mercado stays R$ 300,00 (already tighter — min-tighten).
- `goal.budgets_applied_at` stamped; `previous_budgets = {"<restaurantes_id>" => 60000}` (only the trimmed category).
- Step 5 is a no-op. Budget alerts now pin to the tighter of standing vs trim (NT-B-05 family, chapter 4). Later raising Restaurantes back to R$ 600,00 in the UI arms the budget_raised warning (NT-GL-08 variant).

**Variants:**
- A goal whose `starts_on` is still next month → the job skips it (cuts land only when the schedule starts).
- A cut on a soft-deleted category → skipped silently.

Pins: `app/services/goals/apply_budget_cuts.rb:16-47`, `app/jobs/goals/apply_budget_cuts_job.rb`, `config/recurring.yml:32-35`

---

**Celebrate, speed-up & abandon**

### WEB-GOAL-04 — speed-up contribute: sobra-bounded extra transfer once the parcel is paid; over-sobra rejected

Seed: `exploratory:seed[6]` (fresh re-seed) · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[6]"`; log in `test-6@azulzin.dev`. Verify this month's savings parcel shows PAID in Compromissos (seed 6 pays [1,1,1]) and the dashboard sobra tile is positive with sobra ≥ 20% of the parcel (offer condition: sobra×5 ≥ monthly_target).
2. Open `/goals/:id` — the speed-up form renders → submit `R$ 100,00`.
3. Probe: submit again with an amount larger than the shown sobra (edit the field).

**Expect:**
- Happy: a posted transfer source→caixinha is created with NO `commitment_id` (a second commitment payment would trip the paid-once index); notice `t('goals.contribute.contributed')` naming the NEW pulled-earlier projected month; the goal page "nesse ritmo" line moves earlier with zero writes to the plan.
- Over-sobra: alert `t('goals.contribute.rejected')` — the offer is RE-DERIVED at POST time; render-time sobra is never trusted.

**Variants:**
- Parcel NOT paid this month → no speed-up form rendered; a direct POST → `.rejected`.
- Sobra < 20% of the parcel → offer nil.
- savings_rate goal → never offered (no date to pull earlier).

Pins: `app/services/goals/speed_up_offer.rb:6-16`, `app/controllers/goals_controller.rb:71-87`, `app/services/goals/progress.rb:51-56`

### WEB-GOAL-06 — celebrate: reach target → auto-conclude → one-shot 🎉 party, quiet strip afterwards; goal_achieved to EVERY member (NT-GL-10)

Seed: `exploratory:seed[15]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[15]"` — active goal exactly R$ 50,00 short of target; log in `test-15@azulzin.dev`. Enable WA prefs (`goal_achieved` defaults true, but WA delivery still needs `whatsapp_consent` + `wa_intro_sent_at`).
2. `/transactions` → transfer `R$ 50,00` from checking into the goal's caixinha.
3. WA path first:
```
bin/rails runner 'Goals::WeeklyCheckDispatchJob.perform_now'
```
   (Visiting `/goals/:id` achieves it too — either path flips the status.)
4. Visit `/goals/:id`. Then RELOAD the page.
5. Check Compromissos and (if this goal had applied cuts) `/categories`.

**Expect:**
- First render: Achieve flips status → 🎉 party section (`goals.show.achieved_title` + `achieved_body` with floor whole-reais amount) + "Criar a próxima" CTA; `celebrated_at` stamped by a guarded one-shot flip.
- RELOAD: party gone, quiet strip remains (small 🎉 line + CTA — pinned post-T3 behavior).
- Savings commitment archived (gone from active Compromissos); if cuts were applied, trimmed budgets restore to their `previous_budgets` values.
- WA: "💙 Meta *<nome>* concluída! Você guardou R$ <alvo>. Que tal a próxima?" — `goal_achieved` is EXEMPT from the weekly WA guard (fires even after a goal_alert the same week). Multi-member delivery (NT-GL-10): on `dev:seed_demo` the push goes to BOTH Marina and Rafael.

**Variants:**
- Visit again days later → still only the quiet strip (`celebrated_at` guard, never re-fires).
- savings_rate goal never auto-achieves (`achieved?` is purchase-only).
- A member without `whatsapp_consent` → their Notification row still exists (dashboard/runner) but no WA (Deliver respects per-member consent).

Pins: `app/controllers/goals_controller.rb:43-52`, `app/views/goals/show.html.erb:14-27`, `app/services/goals/achieve.rb:8-21`, `app/jobs/goals/notify_member_job.rb:34-37,125-132`, `test/e2e/notifications/goals_test.rb:219-243`

### WEB-GOAL-07 — abandon active goal: guardado stays, commitment archived, cuts reverted; discard draft

Seed: `exploratory:seed[9]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[9]"`; log in `test-9@azulzin.dev`. Note the goal's caixinha balance at `/bank_accounts` and re-arm the cut so the abandon revert is observable (seed 9 ships with Restaurantes raised back to R$ 600,00 and `budgets_applied_at` already stamped): `bin/rails runner 'g=User.find_by!(email_address:"test-9@azulzin.dev").account.goals.where(status:"active").sole; g.update_columns(budgets_applied_at: nil); Goals::ApplyBudgetCutsJob.perform_now'` — `/categories` now reads Restaurantes R$ 400,00.
2. Visit `/goals/:id` → click "Abandonar" (PATCH `/goals/:id/abandon`).

**Expect:**
- Redirect to `/goals` with `t('goals.abandon.abandoned')` notice; goal listed under closed with an "abandonada" badge.
- Caixinha balance UNCHANGED ("guardado continua guardado" — never a destroy).
- Commitment archived (stops denting sobra, no more parcel reminders; past paid occurrences keep their `commitment_id`).
- Restaurantes budget back to R$ 600,00.

**Variants:**
- **EXPLORATORY GAP (product-decision flag):** click Abandonar on an ACHIEVED goal (e.g. seed 15 after WEB-GOAL-06) — `Abandon.call` returns false (guard) but the controller ignores the result and still flashes the "abandoned" success while nothing changed (`goals_controller.rb:124-127`). Real behavior: status stays achieved. Flagged per the spec-vs-code rule.
- Draft: "Descartar" (DELETE `/goals/:id`) destroys it; a WA GoalConversation pointing at it survives (`dependent: :nullify`).

Pins: `app/services/goals/abandon.rb:7-19`, `app/controllers/goals_controller.rb:124-132`, `app/services/goals/revert_budget_cuts.rb`
## 4. Reminders, budgets, summaries & the notification spine

This chapter proves the proactive layer end to end: reminder/budget/summary sweeps, the delivery gates (consent, quiet hours, daily cap, sidecar), preferences, retention, exports and receipts. Primary seeds: `exploratory:seed[5]` (reminders, test-5@azulzin.dev, JID `5511910000005@c.us`) and `exploratory:seed[4]` (calibrated budgets, test-4@azulzin.dev, JID `5511910000004@c.us`); `dev:seed_demo`, seed 9 and seed 12 appear as one-offs. The spine makes ZERO AI calls — everything here is deterministic except WA-CAP-12 and one NT-R-07 variant. **"Push-ready(N)"** below means: run the seed, sign in as test-N@azulzin.dev / test1234, open `/notification_preferences`, turn "Avisos no WhatsApp" ON and set quiet-hours start = end (e.g. 3/3 — Deliver reads the REAL America/Sao_Paulo clock; the default 21→8 window silently downgrades night-time runs to dashboard-only), save, then in the http://localhost:3001 simulator click "+ adicionar número" and add the JID the seed printed. Re-running the seed is the cheapest reset between takes (wipes rows, claims, dedup AND the daily cap); `Notification.where(user: u).delete_all` in a runner does the same without reseeding. Remember: the in-app Notification row (bell / dashboard) is the reliable observable; the WA bubble in the simulator is the bonus.

### NT-R-01 — Bill-due reminder fires at lead days with exact pt-BR body
Seed: `exploratory:seed[5]` · AI: deterministic

**Steps:**
1. Make test-5 push-ready(5). The seed already holds "Condomínio" R$ 480,00 due TOMORROW (lead_days default 1).
2. Run the sweep:
```
bin/rails runner 'u=User.find_by!(email_address:"test-5@azulzin.dev"); Reminders::NotifyMemberJob.perform_now(u.account.id, u.id)'
```
3. Check the simulator chat for `5511910000005@c.us` and `/dashboard`.

**Expect:** the simulator receives exactly `🔔 Sua conta *Condomínio* (R$ 480,00) vence amanhã. 💙` (key `whatsapp.replies.notifications.bill_due.one`). Dashboard shows the same alert with a "Pagar" button. One Notification row kind=bill_due, period_key = the due date, whatsapp_sent_at set. (Seed 5's full sweep emits other events too — Luz overdue, card closing, Freela; focus on the Condomínio body here, the rest have their own scenarios below.)

**Variants:**
- NT-R-06 lead 0: set "lead days" (bill_reminder_lead_days) to 0 on `/notification_preferences` → tomorrow's bill records NO row at all (outside window).
- NT-R-06 lead 7: create a bill due `Date.current+8` → silent; due `+7` → fires with the `.other` body "vence em 7 dias".
- bill_reminders toggle OFF (Avisos screen): job returns before Scan → NO row, nothing on dashboard either (job-level gate, `reminders/notify_member_job.rb:25`).
- "vence hoje" zero-variant: a commitment with schedule_day = today's day → `🔔 Sua conta *X* (…) vence hoje. 💙`.
- Reset rows (or re-seed) between variants — the daily cap (3 pushes/day) otherwise eats later takes.

Pins: `app/services/reminders/scan.rb:44-47`, `app/jobs/reminders/notify_member_job.rb:25-29`, `config/locales/pt-BR.yml:1441-1445`, `test/e2e/notifications/reminders_test.rb:7-14`

### NT-R-02 — Bill overdue nudges inside 3-day grace, stays silent outside
Seed: `exploratory:seed[5]` · AI: deterministic

**Steps:**
1. Make test-5 push-ready(5). The seed holds "Luz" R$ 185,00 overdue 2 days (inside grace) and "Água" R$ 95,00 overdue 5 days (outside OVERDUE_GRACE_DAYS=3).
2. Run the reminders sweep (same runner as NT-R-01).
3. Count overdue rows:
```
bin/rails runner 'puts Notification.where(kind: "bill_overdue").count'
```

**Expect:** exactly one overdue message in the simulator: `⚠️ Sua conta *Luz* (R$ 185,00) venceu há 2 dias. Já pagou?`. Água produces NO Notification row at all — the count above is 1.

**Variants:**
- A bill due yesterday → `.one` body "venceu ontem. Já pagou?".
- Pay Luz via the hub (`/transactions` → Compromissos → "Pagar") before the sweep → no overdue nudge.

Pins: `app/services/reminders/scan.rb:23`, `app/services/reminders/scan.rb:48-52`, `config/locales/pt-BR.yml:1446-1448`

### NT-R-07 — Already-paid bill skips the reminder; same-day re-run is a no-op
Seed: `exploratory:seed[5]` · AI: deterministic (web-pay path; one live-AI variant)

**Steps:**
1. Make test-5 push-ready(5).
2. BEFORE any sweep, pay Condomínio in the web hub: `/transactions` → Compromissos row → "Pagar".
3. Run the reminders sweep runner (NT-R-01).
4. Run the exact same runner a second time.

**Expect:** first sweep: NO Condomínio message (`occ.paid?` skips it, scan.rb:42) — the other seed events (Luz overdue, card closing, Freela) still arrive. Second run same day: zero new messages, zero new rows — `record!` dedups on (user, kind, subject, period_key) and the claim (whatsapp_sent_at) blocks a re-send. Deterministic web-pay path — no AI key needed.

**Variants:**
- AI-dependent: instead of the web, type `paguei o condomínio` in the :3001 simulator as `5511910000005@c.us` BEFORE the sweep (needs live Groq/LLM key; pay-commitment intent) — same silence expected.

Pins: `app/models/notification.rb:26-34`, `app/services/notifications/deliver.rb:72-75`, `test/e2e/notifications/reminders_test.rb:117-133`

### NT-R-03 — Card closing and card due reminders carry the composed fatura cents
Seed: `exploratory:seed[5]` · AI: deterministic

**Steps:**
1. Make test-5 push-ready(5). The seed card closes TOMORROW with R$ 250,00 already on the open fatura.
2. Run the reminders sweep runner (NT-R-01).
3. For the card_due config: in `bin/rails console`, locate the seed card and run the map-verbatim reconfig `card.update!(bill_due_day: (Date.current+1).day, closing_offset_days: 7)` keeping one card expense ~10 days back; clear the user's Notification rows; re-run the sweep.

**Expect:** closing config: `📄 A fatura do *<card>* fecha amanhã — R$ 250,00 até agora.` (running open-bill total; the map pinned `*Nubank*` on the demo card — use the seed card's name). Due config: `📄 A fatura do *<card>* (R$ 250,00) vence amanhã. 💙` (closed-bill amount). Cross-check the cents against the card tile on `/transactions`.

**Variants:**
- NT-R-04 is covered by the due config above.
- Card without `billing_configured?` (no bill_due_day) → no card events at all (scan.rb:68).
- `closing_offset_days: 0`: closing and due land the same day → BOTH kinds fire, once each (scan.rb:74-76).

Pins: `app/services/reminders/scan.rb:68-85`, `config/locales/pt-BR.yml:1449-1456`, `test/e2e/notifications/reminders_test.rb:44-65`

### NT-R-05 — Expected income nags unless a deposit within ±10% already landed
Seed: `exploratory:seed[5]` · AI: deterministic

**Steps:**
1. Make test-5 push-ready(5). The seed holds income "Freela" R$ 1.200,00 expected TOMORROW.
2. Mark Condomínio and Luz as paid in the hub first (removes two reminder events so the Freela push stays under the daily cap of 3).
3. Variant A (no deposit): run the reminders sweep runner (NT-R-01).
4. Variant B: delete the Freela rows between variants —
```
bin/rails runner 'Notification.where(kind: "income_expected").delete_all'
```
   then add a posted income of R$ 1.092,00 (9% off) dated yesterday on the checking account via `/transactions`, and re-run the sweep.
5. Variant C: replace the deposit with R$ 1.068,00 (11% off), clear rows again, re-run.

**Expect:** A and C: `💰 Seu *Freela* de R$ 1.200,00 deve cair amanhã. 💙`. B (within ±10%): silent, no row — `MonthSummary#income_received?` matches the unlinked deposit.

**Variants:**
- Deposit exactly 10% off (R$ 1.080,00) — probe the boundary manually (spec: ±10% inclusive match suppresses).
- Income marked received via the hub before the sweep → silent.

Pins: `app/services/reminders/scan.rb:91-104`, `test/e2e/notifications/reminders_test.rb:68-90`

### NT-B-01 — Budget bands: warn at 88,3%, breach at 108%, fire at exactly 80,000%, silent at 79,997%
Seed: `exploratory:seed[4]` · AI: deterministic

Seed 4 IS the calibrated account: budgets Mercado R$ 1.500 / Restaurantes R$ 600 / Transporte R$ 450 / Lazer R$ 350, with current-month spend Mercado R$ 1.325,00 (88,33%) · Restaurantes R$ 647,80 (108%) · Transporte R$ 360,00 (exactly 80%) · Lazer R$ 279,99 (79,997%).

**Steps:**
1. Make test-4 push-ready(4).
2. Run the budget sweep:
```
bin/rails runner 'u=User.find_by!(email_address:"test-4@azulzin.dev"); Budgets::NotifyMemberJob.perform_now(u.account.id, u.id)'
```

**Expect:** exactly three pushes: `👀 *Mercado* já está em R$ 1.325,00 de R$ 1.500,00 este mês. Faltam R$ 175,00.` · `⚠️ *Restaurantes* passou do combinado: R$ 647,80 de R$ 600,00 este mês.` · `👀 *Transporte* já está em R$ 360,00 de R$ 450,00 este mês. Faltam R$ 90,00.` Lazer (one centavo under 80%) has NO row. Breach wins: Restaurantes gets no warn alongside. NOTE: default daily cap 3 means all three just fit — a 4th event the same day would be dashboard-only.

**Variants:**
- NT-B-03 boundary: bump Lazer spend by 1 centavo (to R$ 280,00 total, exactly 80%) and re-run NEXT week (same month period_key dedups within the week — delete the rows to retest) → warn fires.
- budget_alerts toggle off → job skips Check entirely, no rows.
- Warn band set above 100 with spend over budget: the "Faltam" left clamps at R$ 0,00, never negative (check.rb:61).

Pins: `app/services/budgets/check.rb:31-35`, `test/e2e/notifications/budgets_test.rb:10-23`, `config/locales/pt-BR.yml:1460-1461`

### NT-B-04 — Custom bands from the Avisos screen move the warn boundary
Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. Reuse the NT-B-01 account; clear its rows first:
```
bin/rails runner 'Notification.where(user: User.find_by!(email_address:"test-4@azulzin.dev")).delete_all'
```
2. In the web UI open `/notification_preferences`, set "Faixa de aviso" to 60 and "Faixa de estouro" to 90, save.
3. Run the same `Budgets::NotifyMemberJob` runner (NT-B-01).

**Expect:** Lazer (79,997%) now warns; Restaurantes (108%) still breaches. Confirms the sweep reads the MEMBER's own bands, not defaults.

**Variants:**
- Validation: warn percent 0 or 201 → 422 re-render with inline error (NotificationPreference validates 1..200).
- Lead days 8 / quiet hour 24 → 422 (0..7 / 0..23).

Pins: `app/controllers/notification_preferences_controller.rb:9-16`, `app/jobs/budgets/notify_member_job.rb:32-37`, `test/e2e/notifications/budgets_test.rb:26-36`

### NT-B-05 — Goal trim binds tighter than the standing budget — copy names the meta
Seed: `exploratory:seed[9]` · AI: deterministic

Seed 9 ships the exact geometry: active goal caps Restaurantes at R$ 400,00 < standing budget R$ 600,00, current-month spend R$ 340,00.

**Steps:**
1. Run `bin/rails "exploratory:seed[9]"`, make test-9 push-ready(9) (JID `5511910000009@c.us`).
2. Run the budget sweep:
```
bin/rails runner 'u=User.find_by!(email_address:"test-9@azulzin.dev"); Budgets::NotifyMemberJob.perform_now(u.account.id, u.id)'
```
3. Inspect the payload: `bin/rails runner 'puts Notification.order(:id).last.payload'`

**Expect:** push `👀 *Restaurantes* já está em R$ 340,00 do combinado da meta *Carro* este mês (R$ 400,00). 💙` — effective_limit = min(60_000 standing, 40_000 trim); payload budget_cents == 40_000, goal_name "Carro". It would be silent against the R$ 600 standing budget alone (340/600 = 57%).

**Variants:**
- Bump spend to R$ 410,00 (add a R$ 70,00 Restaurantes expense via `/transactions`, clear rows, re-run) → budget_breach_goal variant `⚠️ *Restaurantes* passou do combinado da meta *Carro*: …`.

Pins: `app/services/budgets/check.rb:48-53`, `app/services/notifications.rb:44-47`, `test/e2e/notifications/budgets_test.rb:40-51`, `config/locales/pt-BR.yml:1462`

### NT-B-06 — Surplus nudge banks the exact sobra — only in the last week, only in the blue
Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Run `bin/rails dev:seed_demo`, make marina push-ready (marina@azulzin.dev / demo1234, JID `5511987654321@c.us` — prefilled in the simulator). She needs a kept caixinha, sobra ≥ R$ 50,00, surplus_nudges toggle on (default).
2. Use the as_of arg to simulate the last week without waiting:
```
bin/rails runner 'u=User.find_by!(email_address:"marina@azulzin.dev"); Budgets::NotifyMemberJob.perform_now(u.account.id, u.id, Date.current.end_of_month)'
```
3. If band alerts land in the same run and claim the daily cap (3) first, the suggestion becomes dashboard-only: instead run the job once WITHOUT as_of first (bands fire, suggestion stays silent mid-month), backdate the claims with `Notification.where(user: u).update_all(whatsapp_sent_at: 1.day.ago)` in a runner, then run the as_of variant.

**Expect:** push `💙 Você fechou o mês com *R$ <sobra exata>* de sobra. Quer guardar esse dindin?` — cents must equal the hub's sobra tile to the centavo. Kind-aware since 2026-07-11: with NO poupança but an investment account, the copy becomes "Quer mandar pra sua conta investimento?" (and the nudge now fires for investment-only households; it used to skip them). The dashboard alert renders with the "guardar" CTA linking to the transactions hero (`app/views/notifications/_alert.html.erb:17-21`). Only ONE suggestion per month across BOTH suggestion kinds.

**Variants:**
- Mid-month (`as_of = Date.current.beginning_of_month+10`) → silent, no row (`last_week_of?` gate).
- In the red (sobra negative) → total silence, not even a rightsize (suggestion.rb:24 — "no blame").
- Sobra R$ 49,99 → below SURPLUS_FLOOR_CENTS, falls through to rightsize or silence.
- No savings account on the account → surplus event impossible (suggestion.rb:36-37).
- Re-run the same runner → no second row (job checks `Notification.exists?` across SUGGESTION_KINDS).

Pins: `app/services/budgets/suggestion.rb:23-39`, `app/jobs/budgets/notify_member_job.rb:39-43`, `app/jobs/budgets/notify_member_job.rb:48`, `test/e2e/notifications/budgets_test.rb:54-74`

### NT-B-07 — Rightsize names the one budget lying hardest against the 3-month median
Seed: `exploratory:seed[4]` · AI: deterministic

Seed 4 carries the median history (Vestuário spend median R$ 420,00) but leaves Vestuário UNBUDGETED — set the lying budget yourself so Rightsize has a candidate (budget ≥ 150% of median). Rightsize only gets its turn when the month's sobra is under R$ 50,00 — surplus wins otherwise, and only one suggestion fires per month across both kinds.

**Steps:**
1. Fresh `bin/rails "exploratory:seed[4]"`, make test-4 push-ready(4), then set the oversized budget:
```
bin/rails runner 'a=User.find_by!(email_address:"test-4@azulzin.dev").account; a.categories.find_by!(name:"Vestuário").update!(monthly_budget_cents: 100_000)'
```
2. Run the job once WITHOUT as_of (the three band pushes fire and fill the daily cap; the suggestion stays silent mid-month), then backdate the claims so the suggestion push isn't cap-eaten:
```
bin/rails runner 'u=User.find_by!(email_address:"test-4@azulzin.dev"); Notification.where(user: u).update_all(whatsapp_sent_at: 1.day.ago)'
```
3. Run the last-week pass:
```
bin/rails runner 'u=User.find_by!(email_address:"test-4@azulzin.dev"); Budgets::NotifyMemberJob.perform_now(u.account.id, u.id, Date.current.end_of_month)'
```
4. If a surplus nudge fires instead, sobra is ≥ R$ 50,00 (precedence working as designed): delete the suggestion row, add a bank expense via `/transactions` large enough to push sobra below R$ 50,00 while staying in the blue, and re-run step 3.

**Expect:** push `💙 *Vestuário*: você combinou R$ 1.000,00, mas costuma gastar R$ 420,00. Dá pra ajustar em Categorias.` (with the R$ 1.000,00 budget set in step 1) — exactly one suggestion, framed as tidying.

**Variants:**
- Only 2 months of history → silent (`monthly.size` must equal WINDOW_MONTHS).
- Budget at 149% of median → silent.

Pins: `app/services/budgets/suggestion.rb:44-57`, `test/e2e/notifications/budgets_test.rb:77-90`, `config/locales/pt-BR.yml:1492`

### NT-B-08 — Weekly budget sweep run twice the same week sends nothing new
Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. Complete one successful NT-B-01 sweep on the calibrated account.
2. Note the simulator message count for `5511910000004@c.us` and `Notification.count` for the user.
3. Run the exact same `Budgets::NotifyMemberJob` runner a second (and third) time.

**Expect:** simulator message count unchanged; Notification row count unchanged. period_key = billing month + kind in the dedup key means re-crossing the same band is silent; a new month re-arms both bands.

Pins: `app/models/notification.rb:26-34`, `app/services/notifications/deliver.rb:72-75`, `test/e2e/notifications/budgets_test.rb:93-103`

### NT-S-01 — Weekly summary digest: composed lines, exact cents, top-3 + outros
Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[4]"`, make test-4 push-ready(4), then set the oversized budget:
```
bin/rails runner 'a=User.find_by!(email_address:"test-4@azulzin.dev").account; a.categories.find_by!(name:"Vestuário").update!(monthly_budget_cents: 100_000)'
```
2. On `/notification_preferences` flip "weekly summary" ON — it defaults FALSE.
3. Run:
```
bin/rails runner 'u=User.find_by!(email_address:"test-4@azulzin.dev"); Summaries::NotifyMemberJob.perform_now(u.account.id, u.id, "weekly")'
```

**Expect:** one push: `📊 *Resumo da semana*` + `Você gastou <total> — <top-3 categories>, outros <rest>.` + `Sobra do mês até agora: <sobra>.` + optional `Contas nos próximos 7 dias: <next 2 bills>.` + `💙`. On the calibrated account the golden is: gastou R$ 2.612,79 — Mercado R$ 1.325,00, Restaurantes R$ 647,80, Transporte R$ 360,00, outros R$ 279,99. Sobra must equal the hub tile to the centavo. period_key = this week's Monday. (The demo household also works — read its exact cents from the hub.)

**Variants:**
- No spend but an upcoming bill → weekly_summary_no_spend body variant (pt-BR.yml:1199).
- Re-run same week → no dupe (period_key = Monday).

Pins: `app/services/summaries/build.rb:36-44`, `app/jobs/summaries/notify_member_job.rb:24-35`, `test/e2e/notifications/summaries_test.rb:9-22`, `config/locales/pt-BR.yml:1493-1496`

### NT-S-02 — Monthly summary recaps the JUST-CLOSED month, red months stated plainly
Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. Make test-4 push-ready(4); flip "monthly summary" ON on `/notification_preferences` (defaults FALSE).
2. Simulate "the 1st" without waiting via as_of — prev_month of as_of = the current month, recapped as closed:
```
bin/rails runner 'u=User.find_by!(email_address:"test-4@azulzin.dev"); Summaries::NotifyMemberJob.perform_now(u.account.id, u.id, "monthly", Date.current.next_month.beginning_of_month)'
```

**Expect:** push `📅 *<Mês> fechou*` + `Entrou X, saiu Y, faturas Z.` + `Sobra do mês: S · guardado: G.` + `Você ficou dentro do combinado em N de M categorias.` The budget line appears only when budgets exist; "dentro" is STRICTLY under budget — exactly-on-budget counts as blown (build.rb:104-110); on seed 4 Restaurantes (108%) must count as fora. A negative sobra renders as `-R$ …` plainly. Seed 4's guardado (R$ 300,00/month into the caixinha) should show in G.

**Variants:**
- Closed month with zero entradas+saidas+guardado → nil, no row (build.rb:53-54).

Pins: `app/services/summaries/build.rb:50-63`, `test/e2e/notifications/summaries_test.rb:25-41`, `config/locales/pt-BR.yml:1497-1501`

### NT-S-03 — Nothing-to-say and toggle-off summaries produce NO row (not just no push)
Seeds: `exploratory:seed[12]` (case A) + `exploratory:seed[4]` (case B) · AI: deterministic

**Steps:**
1. Case A (empty week): run `bin/rails "exploratory:seed[12]"` (account bootstrapped, wizard never run, zero transactions). test-12 cannot reach `/notification_preferences` (the onboarding gate redirects — X-EXP-08), so flip the pref by runner, then dispatch:
```
bin/rails runner 'User.find_by!(email_address:"test-12@azulzin.dev").notification_prefs.update!(weekly_summary: true)'
```
```
bin/rails runner 'u=User.find_by!(email_address:"test-12@azulzin.dev"); Summaries::NotifyMemberJob.perform_now(u.account.id, u.id, "weekly")'
```
2. Case B (toggle off): fresh `bin/rails "exploratory:seed[4]"`, leave weekly_summary at its FALSE default, run the same runner against test-4.
3. Verify: `bin/rails runner 'u=User.find_by!(email_address:"<user>"); puts Notification.exists?(user: u, kind: "weekly_summary")'`

**Expect:** both cases: `Notification.exists?(user: u, kind: "weekly_summary")` is false and the simulator stays empty — the toggle is checked in the JOB (no dashboard "opt-out surprise"), and an empty week returns nil before `record!`.

**Variants:**
- NT-S-04 is case B above.

Pins: `app/jobs/summaries/notify_member_job.rb:29-32`, `app/services/summaries/build.rb:39`, `test/e2e/notifications/summaries_test.rb:44-66`

### NT-G-03 — No WhatsApp consent (the default) = dashboard-only for every kind
Seed: `exploratory:seed[5]` · AI: deterministic

Seed 5 ships with whatsapp_consent at its DEFAULT (off) and the owner WA-verified — exactly this scenario. Do NOT touch the consent toggle before step 2.

**Steps:**
1. Run the seed, sign in as test-5, add JID `5511910000005@c.us` in the simulator. Leave `/notification_preferences` alone.
2. Run the reminders sweep runner (NT-R-01, against test-5).
3. Then flip "Avisos no WhatsApp" ON at `/notification_preferences` (and set quiet hours to an empty window, e.g. 3/3), and re-run the sweep the same day.

**Expect:** step 2: dashboard shows the bill_due alert; the :3001 simulator receives NOTHING; the row's whatsapp_sent_at stays nil (claim not burned). Step 3: the push goes out (row was unclaimed).

**Variants:**
- NT-G-04 phone unverified / JID blank: `bin/rails runner 'User.find_by!(email_address:"test-5@azulzin.dev").update!(whatsapp_jid: nil)'` → dashboard-only.

Pins: `app/services/notifications/deliver.rb:32`, `db/schema.rb:321`, `test/e2e/notifications/gates_test.rb:50`

### NT-G-06 — Quiet hours suppress the push, empty window releases it
Seed: `exploratory:seed[5]` · AI: deterministic

Deliver reads the REAL São Paulo clock — no travel possible manually.

**Steps:**
1. Make test-5 push-ready(5) but on `/notification_preferences` set the quiet-hours window to COVER the current SP hour (e.g. at 15h SP set start 15 / end 16), save.
2. Run the reminders sweep runner (NT-R-01, against test-5).
3. Set start == end (e.g. 3/3 — empty window, never quiet), save, and re-run the sweep.

**Expect:** first run: dashboard row only, no simulator message, whatsapp_sent_at nil, NOT re-queued. Second run same day: push delivered once (claim was never burned). Default 21→8 wraps midnight — running any sweep at night without adjusting prefs silently yields dashboard-only.

**Variants:**
- Wrap-midnight check: start 21 / end 8, run at 22h SP → suppressed; at 09h SP → delivers.

Pins: `app/services/notifications/deliver.rb:54-57`, `test/e2e/notifications/gates_test.rb:83`

### NT-G-07 — Daily cap: 4 events, 3 pushes, 4 dashboard rows — cap throttles push, never truth
Seed: `exploratory:seed[5]` · AI: deterministic

A single fresh seed-5 sweep natively lands FOUR reminder events: Condomínio bill_due + Luz bill_overdue (in grace) + card closing + Freela income_expected (Água is outside grace and records nothing).

**Steps:**
1. Fresh `bin/rails "exploratory:seed[5]"`, make test-5 push-ready(5).
2. Run the reminders sweep runner (NT-R-01, against test-5) once.
3. Count unclaimed rows:
```
bin/rails runner 'u=User.find_by!(email_address:"test-5@azulzin.dev"); puts Notification.where(user: u, whatsapp_sent_at: nil).count'
```

**Expect:** simulator shows exactly 3 messages; `/dashboard` shows all 4 alerts; exactly one Notification row has whatsapp_sent_at nil. Next SP day the cap re-arms (verify by seeding a new bill due tomorrow and re-running).

**Variants:**
- The cap counts CLAIMS today: manually `Notification.where(user: u).update_all(whatsapp_sent_at: 1.day.ago)` → a fresh event pushes again.

Pins: `app/services/notifications/deliver.rb:13`, `app/services/notifications/deliver.rb:61-63`, `test/e2e/notifications/reminders_test.rb:137-140`

### NT-G-05 — Sidecar disconnected: dashboard-only, no ghost send; next sweep after reconnect delivers once
Seed: `exploratory:seed[5]` · AI: deterministic

Deliver reads the WhatsappConnection DB row, so the outage is simulated deterministically without killing the process.

**Steps:**
1. Make test-5 push-ready(5).
2. `bin/rails runner 'WhatsappConnection.instance.mark_disconnected!'`
3. Run the reminders sweep runner (NT-R-01, against test-5); observe dashboard + simulator.
4. `bin/rails runner 'WhatsappConnection.instance.mark_connected!'`
5. Run the reminders sweep runner again.

**Expect:** while down: dashboard rows exist, whatsapp_sent_at nil, simulator silent, nothing raised. After reconnect + re-dispatch: each unclaimed row is re-offered by the sweep and delivered exactly ONCE (Condomínio's body appears a single time; the daily cap of 3 still applies) — no automatic retry ever fires on its own.

**Variants:**
- NT-G-11 sidecar process actually dead mid-send (stop the foreman `sidecar` line): WhatsappService returns `{error:}`, no crash; note the claim IS burned in this direction — the message is lost, never duplicated.

Pins: `app/services/notifications/deliver.rb:47-49`, `app/models/whatsapp_connection.rb:41`, `test/e2e/notifications/gates_test.rb:70`

### NT-G-10 — First-ever delivered push carries the 'responda parar' footer exactly once
Seed: `exploratory:seed[5]` · AI: deterministic

**Steps:**
1. Fresh `bin/rails "exploratory:seed[5]"`, make test-5 push-ready(5) — do NOT let wa_intro_sent_at get stamped; the runner below forces it nil anyway. Seed 5's sweep sends multiple pushes in one pass, which is what the assertion needs.
2. Run:
```
bin/rails runner 'u=User.find_by!(email_address:"test-5@azulzin.dev"); u.notification_prefs.update!(wa_intro_sent_at: nil); Reminders::NotifyMemberJob.perform_now(u.account.id, u.id)'
```

**Expect:** in the simulator, ONLY the first message ends with `Responda *parar* para desativar estes avisos.`; the later pushes in the SAME sweep do not (update_column stamps the cached prefs object). wa_intro_sent_at now set.

Pins: `app/services/notifications/deliver.rb:108-115`, `config/locales/pt-BR.yml:1396`, `test/e2e/notifications/gates_test.rb:151`

### WA-ID-09 — 'parar' from WhatsApp kills consent instantly — deterministic, zero LLM
Seed: `exploratory:seed[5]` · AI: deterministic (works with NO AI key — the stop pre-pass runs before any extraction)

**Steps:**
1. Make test-5 push-ready(5) (consent ON).
2. In the :3001 simulator, as JID `5511910000005@c.us`, type exactly: `parar` (also try `para de me avisar`, `não quero mais avisos`).
3. Check `/notification_preferences`, then run a reminders sweep.

**Expect:** instant reply `Prontinho, parei os avisos por aqui. É só reativar em *Conta e membros → Avisos* quando quiser. 💙` sent ONCE; whatsapp_consent flips false (toggle now off on `/notification_preferences`); the subsequent reminder sweep records rows but pushes nothing. Re-enable is in-app only.

**Variants:**
- `gastei 50 sem parar` must NOT hijack — it proceeds to expense extraction (completing the capture needs a live Groq/LLM key; the non-hijack itself is deterministic).
- `PARAR!!` with punctuation/case/accents still matches (normalized + anchored regex).

Pins: `app/services/whatsapp/interpreter.rb:31`, `app/services/notifications/stop_command.rb:12-24`, `config/locales/pt-BR.yml:1397`

### NT-X-02 — Dashboard alert dismiss removes the banner; cross-user/cross-account id is a 404
Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Run `bin/rails dev:seed_demo`. As marina, run any sweep so she has at least one Notification row (consent not required — the dashboard row is inherent). Sign rafael@azulzin.dev into a second browser session.
2. Note the notification id from the DOM (`notification_<id>`) on marina's `/dashboard`.
3. As marina, click the alert's dismiss (X).
4. As rafael, from HIS devtools console (a bare curl PATCH dies on CSRF before the tenancy check): `fetch('/notifications/<marina_row_id>/dismiss', {method:'PATCH', headers:{'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content}}).then(r => console.log(r.status))`

**Expect:** marina: banner removed live (Turbo Stream), dismissed_at set, gone on reload; rafael's own dashboard unaffected. Rafael's PATCH on marina's id: 404 — scoping is Current.user + Current.account, never a policy check that leaks existence.

**Variants:**
- bill_due alert "Pagar" button: paying from the banner also dismisses it and marks the occurrence paid (double-click → one payment).

Pins: `app/controllers/notifications_controller.rb:6`, `app/views/notifications/dismiss.turbo_stream.erb`, `app/views/notifications/_alert.html.erb:56-57` (dismiss button; "Pagar" at :21-31)

### NT-X-04 — Retention purges rows whose period_key is past the window, keeps recent
Seed: `exploratory:seed[5]` (any user with rows) · AI: deterministic

**Steps:**
1. Run any sweep so a few Notification rows exist, then plant one artificially old row:
```
bin/rails runner 'n=Notification.last.dup; n.update!(period_key: 60.days.ago.to_date)'
```
2. Run the purge (default 45 days):
```
bin/rails runner 'puts NotificationRetentionJob.perform_now'
```
   (or force: `NotificationRetentionJob.perform_now(retain_days: 0)` purges everything with period_key before today)

**Expect:** returns the purge count; rows with period_key older than the cutoff are gone from the dashboard, today's rows survive. Safe for dedup — scanners only look at current periods, purged rows can never re-fire a push.

**Variants:**
- ENV `NOTIFICATION_RETENTION_DAYS` override respected (retention_days reader).

Pins: `app/jobs/notification_retention_job.rb:12-14`, `config/recurring.yml:28`, `test/e2e/notifications/gates_test.rb:138`

### NT-G-12 — Couple: each member gets their own row and push at their own prefs
Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Run `bin/rails dev:seed_demo` (marina + rafael, both WA-verified; JIDs `5511987654321@c.us` and `5511976543210@c.us` prefilled in the :3001 simulator — make sure BOTH chats are open).
2. Turn consent ON for both (each signs into `/notification_preferences`; empty quiet window). Turn rafael's bill_reminders toggle OFF on HIS Avisos screen.
3. Ensure one bill due tomorrow exists on the account (create a fixed commitment via the Compromissos section of `/transactions` if needed).
4. Fan out per membership:
```
bin/rails runner 'a=User.find_by!(email_address:"marina@azulzin.dev").account; AccountMembership.where(account: a).pluck(:account_id,:user_id).each { |aid,uid| Reminders::NotifyMemberJob.perform_now(aid, uid) }'
```

**Expect:** marina's JID gets the push and her dashboard the row; rafael gets NEITHER row nor push (his job-level toggle) — toggles are per member, account data fans out per membership. Flip rafael's toggle on and re-run: he gets his own row + push, marina dedups.

**Variants:**
- Member removed from the account between enqueue and run → job returns silently (notify_member_job.rb:22).

Pins: `app/jobs/reminders/daily_dispatch_job.rb:13-14`, `test/e2e/notifications/gates_test.rb:189`

### NT-X-03 — en-US recipient gets en-US push copy with money still in R$
Seed: `exploratory:seed[5]` · AI: deterministic

The pt-BR launch pin blocks the web path, but Deliver reads user.locale directly — force it via console.

**Steps:**
1. Make test-5 push-ready(5) (Condomínio due tomorrow is the vehicle).
2. `bin/rails runner 'User.find_by!(email_address:"test-5@azulzin.dev").update!(locale: "en-US")'`
3. Run the reminders sweep runner (NT-R-01, against test-5).
4. RESET the locale to pt-BR afterwards.

**Expect:** push body is the en-US bill_due template with the amount still formatted `R$ 480,00`-style BRL (never `$`). The dashboard banner, by contrast, renders in the REQUEST locale (pinned pt-BR) — the two surfaces legitimately differ here.

Pins: `app/services/notifications/deliver.rb:92-99`, `test/e2e/notifications/gates_test.rb:176`

### WEB-EXP-02 — Export the ledger: presets, three formats, garbage format falls back
Seed: `dev:seed_demo` · AI: deterministic (no AI, no jobs)

**Steps:**
1. Sign in as marina (months of transactions).
2. Visit `/exports/new`, pick preset + format, download.
3. Hit the direct URLs: `/exports.csv?preset=year` · `/exports.xlsx` (default current month) · `/exports.pdf?preset=last_3_months` · custom: `/exports.csv?preset=custom&from=2026-05-01&to=2026-05-31` · garbage: `/exports.exe?preset=all` and `/exports?preset=custom&from=banana`

**Expect:** CSV opens with one row per transaction, summed cents matching the hub month totals exactly (WEB-TX-02); xlsx and pdf download with localized filename (`t('.filename')`). Garbage format serves xlsx (whitelist fallback); unparseable custom dates become nil bounds (unbounded side). All rows belong to the current account only.

**Variants:**
- X-EXP-13 tenancy (§9): sign into a second account in another browser, export — no cross-account rows (seed 14's "VAZAMENTO LTDA" R$ 666,66 canary must never appear).
- Unknown preset → falls back to current month (smallest range).
- Signed out → redirected to login, no data.

Pins: `app/controllers/exports_controller.rb:12-16`, `app/controllers/exports_controller.rb:38-47`, `app/services/exports/ledger.rb`

### WEB-TX-08 — Receipt upload gates (see §5)
Covered in full in §5 (WEB-TX-08): magic-byte and size gates, authenticated proxy, signed-out denial.
### WA-CAP-12 — WhatsApp receipt image becomes the transaction's durable receipt; duplicate attaches instead of double-posting
Seed: `dev:seed_demo` · AI: live-AI (vision extraction — Groq/vision provider configured in dev; LIVE KEY REQUIRED)

**Steps:**
1. Make marina push-ready; have a legible photo of a simple receipt (merchant + total). For the dedup half, a posted expense matching the same merchant/amount/date should already exist.
2. In the :3001 simulator send the receipt image to the bot as `5511987654321@c.us`.
3. Send the SAME image again (or a receipt matching the pre-existing posted charge).

**Expect:** first send: expense created (or parked pending on low confidence) AND the image blob copied to transaction.receipt — verify the thumbnail on the row in `/transactions` and via `/transactions/<id>/receipt`. Second send: NO new transaction; the receipt attaches to the already-posted matching row (the T3 receipt-dup fix). The receipt survives WhatsappRetentionJob purging the WA media copy (X-EXP-01: the blob is attached to the transaction, not referenced).

**Variants:**
- Non-receipt image (a selfie) → not_receipt flow: polite decline / caption fallback, no transaction (WA-CAP-33/34).
- AI failure/timeout → fail-and-tell degrade reply, message not silently dropped (WA-CAP-30). Force deterministically by restarting with `OPENROUTER_API_KEY=broken bin/dev-fake`.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:85-95`, `app/jobs/process_inbound_whatsapp_job.rb:138-142`, `app/services/whatsapp/decider.rb:135-152`

### NT-EXP-01 — Avisos preferences screen round-trip and validation bounds
Seed: `exploratory:seed[5]` (any signed-in member) · AI: deterministic

The NotificationPreference row is created lazily on first save — a brand-new user has no row until visiting/saving.

**Steps:**
1. Sign in and visit `/notification_preferences`.
2. Save valid changes: lead days 3, quiet 22→7, warn 70 / breach 95.
3. Force invalid values (edit the number inputs / devtools to bypass min/max): lead_days 9, quiet_hours_start 24, warn_percent 0, breach 201; save.

**Expect:** valid save: redirect with the `.saved` pt-BR flash, values persisted and used by the next sweep. Invalid: 422 re-render of :show with activerecord inline errors in pt-BR; nothing persisted. Defaults visible on first visit: lead 1, quiet 21→8, warn 80, breach 100, consent OFF, weekly/monthly summary OFF, goal_alerts OFF, bill/budget/surplus/goal_achieved ON.

**Variants:**
- Forged param outside the params.expect list (e.g. user_id) is ignored — prefs are strictly Current.user's.

Pins: `app/controllers/notification_preferences_controller.rb:9-16`, `app/models/notification_preference.rb:8-12`, `app/views/notification_preferences/show.html.erb`
## 5. Web journeys — auth, onboarding, ledger, instruments

This chapter walks the whole web surface: signup/verification/reset, the onboarding wizard, the transactions hub (CRUD, filters, month summary, transfers, receipts, WA-parked tray), bank accounts and credit-card billing math, categories + backfill, commitments/occurrences, dashboard, account settings, and the pt-BR locale pin.
Baseline data is `bin/rails dev:seed_demo` (marina@azulzin.dev / rafael@azulzin.dev, `demo1234` — WIPES and recreates "Família Andrade" with 4 months of calibrated history). Fresh-signup scenarios use non-demo emails (`teste+n@azulzin.dev`) so the seed wipe never collides. The demo numbers drift the moment you add/edit rows — re-run the seed whenever a scenario needs the frozen figures. Run destructive scenarios (MU-08, bank-account deletes) LAST or re-seed after.

### WEB-AUTH-01 — Signup → verification email → confirm link signs in → lands in wizard

Seed: none (fresh signup) · AI: deterministic

**Steps:**
1. Open http://localhost:3000/registration/new.
2. Fill email `teste+1@azulzin.dev`, password `senha1234` (min 8 chars), confirmation the same → submit. Dev has NO allowlist (prod-only, `config/environments/production.rb:91`).
3. letter_opener pops the verification email in a new browser tab — click the `/email_verification/:token` link.

**Expect:** Flash `t('registrations.create.check_email')` after submit; the confirmation click both verifies AND starts a session (`t('email_verifications.show.confirmed')`), redirecting to `/` → onboarding wizard profile step.

**Variants:**
- Password < 8 chars or confirmation mismatch → inline errors, form re-rendered 422 (`user.rb:41`).
- Duplicate email → uniqueness inline error (`user.rb:38`).

Pins: `app/controllers/registrations_controller.rb:12-31`, `app/controllers/email_verifications_controller.rb:7-14`, `test/system/journeys/onboarding_journey_test.rb:8`, `config/environments/development.rb:44`

### WEB-AUTH-02 — Login rejections: wrong password and unverified account

Seed: dev:seed_demo + one unverified signup · AI: deterministic

**Steps:**
1. Run `bin/rails dev:seed_demo`; also sign up `teste+2@azulzin.dev` but do NOT click its letter_opener link (stays unverified).
2. At http://localhost:3000/session/new sign in as `marina@azulzin.dev` with password `errada123`.
3. Then sign in as `teste+2@azulzin.dev` with its correct password.

**Expect:** (a) alert `t('sessions.create.invalid')`; (b) alert `t('sessions.create.unverified')`. No session cookie set in either case — still on the sign-in page, and `/dashboard` redirects back.

Pins: `app/controllers/sessions_controller.rb:8-19`

### WEB-AUTH-03 — Auth rate limits: 11th login attempt and 6th verification resend inside 3 minutes

Seed: none · AI: deterministic

**Steps:**
1. Rate limit is per-IP+action; any email works. If throttling doesn't trip, enable the dev cache first: `bin/rails dev:cache` (controller caching is what `rate_limit` needs, `development.rb:21`) and restart.
2. Submit the login form at `/session/new` 11 times in under 3 minutes with any wrong password.
3. Separately, from the sign-in page use the "reenviar" link (POST `/email_verification`) 6 times.

**Expect:** Attempt 11 (login) and attempt 6 (resend) redirect with alert `t('shared.rate_limited')` instead of the normal `.invalid`/`.sent` replies.

**Variants:**
- Registration create and password-reset request throttle the same way at 10/3min.

Pins: `app/controllers/sessions_controller.rb:3`, `app/controllers/email_verifications_controller.rb:3-4`, `app/controllers/registrations_controller.rb:3-4`, `app/controllers/passwords_controller.rb:4`

### WEB-AUTH-04 — Verification token abuse: garbage and expired tokens never sign in

Seed: none (one unverified signup) · AI: deterministic

**Steps:**
1. Sign up `teste+3@azulzin.dev`; copy the verification link from letter_opener but do NOT click it yet.
2. Visit http://localhost:3000/email_verification/GARBAGE123.
3. Invalidate the copied token by changing the email in console:
```
bin/rails runner 'User.find_by(email_address:"teste+3@azulzin.dev").update!(email_address:"teste+3b@azulzin.dev")'
```
4. Now visit the stale link captured in step 1.

**Expect:** Both redirect to `/session/new` with alert `t('email_verifications.show.invalid')`; no session started, user stays unverified.

**Variants:**
- Resend for an already-verified or unknown email gives the identical `t('.sent')` notice — no enumeration (`email_verifications_controller.rb:16-19`).

Pins: `app/controllers/email_verifications_controller.rb:7-14`, `app/models/user.rb:57`

### WEB-AUTH-05 — Password reset chain: request → email → reset → ALL sessions destroyed

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Open a SECOND browser (or private window) signed in as marina — this proves the session kill.
2. Browser A: `/passwords/new` → submit `marina@azulzin.dev`.
3. Open the letter_opener reset email → follow `/passwords/:token/edit` → set a new password.
4. Browser B: refresh `/dashboard`.

**Expect:** The request step always answers `t('passwords.create.notice')` (same for unknown emails — no enumeration); after the update, notice `t('passwords.update.success')`, and Browser B's session is dead (redirected to sign-in) because `sessions.destroy_all` ran.

**Variants:**
- Unknown email at the request step → identical notice, no email sent.

Pins: `app/controllers/passwords_controller.rb:9-27`, `test/e2e/web/auth_journeys_test.rb`

### WEB-AUTH-06 — Password reset failures: invalid/expired token and confirmation mismatch

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Get one real reset link for marina from letter_opener (as in WEB-AUTH-05).
2. Visit `/passwords/BOGUS/edit`.
3. On the valid reset form, submit password `novaSenha1` with confirmation `diferente1`.

**Expect:** (a) redirect to `/passwords/new` with alert `t('passwords.invalid_token')`; (b) redirect back to the edit form with alert `t('passwords.update.mismatch')` — password unchanged, sessions intact.

Pins: `app/controllers/passwords_controller.rb:20-34`

### WEB-ONB-01 — Onboarding wizard end-to-end: profile → accounts (≥1) → incomes (≥1) → cards (skip) → hub

Seed: none (fresh verified signup) · AI: deterministic

**Steps:**
1. Sign up + confirm `teste+4@azulzin.dev` (WEB-AUTH-01 flow) — you land on `/onboarding`.
2. Profile step: name `Teste Web`, phone `11999990044` → Continuar.
3. Accounts step: add a bank account via the inline Turbo form — institution Itaú, saldo `R$ 1.000,00` → Continuar.
4. Incomes step: add `Salário`, `R$ 3.500,00`, dia 5, destino the created account → Continuar.
5. Cards step: click "Concluir" without adding a card.

**Expect:** Each Continuar advances one step; finishing sets `user.onboarded?` and redirects to `/dashboard` with notice `t('onboarding.finished')`. Default pt-BR categories exist once at `/categories` (seeded by `User#onboard!` at the wizard's finish — NOT at bootstrap, so they don't exist during the wizard steps).

**Variants:**
- Continuar on accounts step with zero accounts → alert `t('onboarding.accounts.need_one')`.
- Continuar on incomes step with zero incomes → alert `t('onboarding.incomes.need_one')`.

Pins: `app/controllers/onboarding_controller.rb:12-42`, `app/controllers/onboarding_controller.rb:105-124`, `test/system/journeys/onboarding_journey_test.rb:19`

### WEB-ONB-02 — Onboarding step forging: deep-link/PATCH a later step with earlier ones incomplete

Seed: none (fresh verified signup, profile NOT completed) · AI: deterministic

**Steps:**
1. With a fresh verified signup that has not filled the profile step, visit http://localhost:3000/onboarding/cards directly.
2. Then (curl or devtools, reusing the page's CSRF token) PATCH `/onboarding/cards` to try to finish.

**Expect:** Both GET and PATCH bounce (redirect) to the resume step `/onboarding/profile` — onboarding cannot be completed with an incomplete profile or zero accounts/incomes.

**Variants:**
- Delete the only bank account after advancing, revisit `/onboarding` → bounced back to the accounts step (WEB-ONB-04).

Pins: `app/controllers/onboarding_controller.rb:14`, `app/controllers/onboarding_controller.rb:25`, `app/controllers/onboarding_controller.rb:51-61`

### WEB-ONB-03 — Onboarding profile validations: overlong name and malformed phone

Seed: none (fresh verified signup on the profile step) · AI: deterministic

**Steps:**
1. Submit the profile form with a 121+ character name.
2. Submit with phone national `123` (fails `\A\d{8,15}\z`).
3. Submit with blank name.

**Expect:** 422 re-render with inline activerecord errors on name/phone; the step never advances — profile is never skippable (the Pular affordance re-checks it server-side).

Pins: `app/models/user.rb:53-54`, `app/controllers/onboarding_controller.rb:87-95`

### WEB-ONB-05 — Owner sets account display name on the profile step

Seed: none (fresh verified signup — owner of its bootstrap solo account) · AI: deterministic

**Steps:**
1. On `/onboarding/profile` fill the "nome da conta" field with `Família Teste` and submit alongside name/phone.

**Expect:** Account renamed — visible later at the `/account` header. Only the owner's submission is honored; an invited member's `account_name` param is ignored (`account_owner?` gate).

Pins: `app/controllers/onboarding_controller.rb:100-103`

### WEB-EXP-11 — Explicit wizard skip (Pular) past instruments

Seed: none (fresh verified signup, profile step done, no bank account) · AI: deterministic

**Steps:**
1. From `/onboarding/accounts` click "Pular" (PATCH `/onboarding/skip`).

**Expect:** `onboard!` runs, redirect to `/dashboard` with `t('onboarding.finished')`. The account has NO instruments, which sets up WEB-TX-03: transactions/commitments creation is blocked until one exists.

**Variants:**
- PATCH `/onboarding/skip` with a blank profile → bounced to `/onboarding/profile` (`resume_step == 'profile'` guard).

Pins: `app/controllers/onboarding_controller.rb:39-42`, `config/routes.rb:51`

### WEB-TX-01 — Add expense in the hub drawer → edit amount in place → soft delete

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Sign in as marina (Itaú anchored `R$ 3.412,55`, Nubank `R$ 2.148,90`, Caixinha `R$ 5.200,00`; 2 cards due day 10).
2. On `/transactions`: "Adicionar" (the + button on Movimentos) → expense `R$ 45,90`, merchant `Farmácia Teste`, category Saúde, débito, instrument Itaú → save.
3. Edit the row (lápis) → change to `R$ 50,00` → save.
4. Delete the row.

**Expect:** Row streams into Movimentos with exactly "R$ 45,90"; Itaú derived balance drops by 4590 centavos on the accounts tile; after the edit it shows "R$ 50,00"; after delete the row leaves every list (soft delete — restorable only via console) with notice `t('transactions.destroy.removed')`.

**Variants:**
- Blank amount/merchant → 422, form kept with inline errors, no row created.

Pins: `app/controllers/transactions_controller.rb:30-54`, `app/controllers/transactions_controller.rb:60-75`, `app/controllers/transactions_controller.rb:117-123`, `app/controllers/transactions_controller.rb:263-272`

### WEB-TX-02 — Month summary figures: entradas / saídas / faturas / guardado / sobra tie out to the centavo

Seed: dev:seed_demo (UNTOUCHED — re-run the seed to reset drift) · AI: deterministic

**Steps:**
1. Sign in as marina and open `/transactions` for the current month (incomes: Salário Marina `R$ 6.500,00` + Salário Rafael `R$ 4.200,00`, day 5; guardado `R$ 300,00`/month into Caixinha).
2. Cross-check the hero tiles against a runner probe:
```
bin/rails runner 'a=User.find_by!(email_address:"marina@azulzin.dev").account_membership.account; s=MonthSummary.new(a, Date.current.beginning_of_month); puts({entradas: s.entradas_cents, saidas: s.saidas_cents, faturas: s.faturas_cents, guardado: s.guardado_cents})'
```

**Expect:** Every on-screen R$ figure equals the runner output formatted pt-BR (`R$ 1.234,56`); entradas includes expected-but-unreceived income; saídas includes projected debit commitments; faturas sums per-card open bills.

Pins: `app/models/month_summary.rb:25-91`, `lib/demo_seed.rb:95-98`, `lib/demo_seed.rb:250-252`, `test/system/journeys/money_screens_test.rb`

### WEB-TX-03 — No instrument at all: needs_instrument prompt; credit purchase without a chosen card 422s

Seed: Pular-skip account from WEB-EXP-11 + dev:seed_demo · AI: deterministic

**Steps:**
1. As the zero-instrument Pular-skip user, on `/transactions` click "Adicionar" (the + button on Movimentos).
2. As marina (2 cards, so no lone-card auto-select), open the drawer, choose crédito, clear/leave the card unselected, submit.

**Expect:** (a) The frame renders the "crie uma conta ou cartão primeiro" prompt (`shared.needs_instrument`) instead of the form — a direct POST gets the same. (b) 422 with the `:instrument_required` base error — NEVER a silent park into the review tray.

Pins: `app/controllers/transactions_controller.rb:9`, `app/controllers/transactions_controller.rb:128-130`, `app/controllers/transactions_controller.rb:41-44`, `app/controllers/application_controller.rb:18-21`

### WEB-TX-04 — Forged cross-account FKs in transaction POST are sanitized to nil

Seed: dev:seed_demo + fresh signup teste+5 · AI: deterministic

**Steps:**
1. Create a second household: sign up + onboard `teste+5@azulzin.dev` (has at least one category). Grab a foreign category id:
```
bin/rails runner 'puts User.find_by!(email_address:"teste+5@azulzin.dev").account_membership.account.categories.first.id'
```
2. As marina, open the drawer form and, in devtools, edit the `category_id` hidden input to the foreign id before submitting a `R$ 10,00` expense.

**Expect:** Row saves with `category_id` NIL (silently dropped) — no cross-tenant write, no 500. The same guard covers `transfer_to_bank_account_id` and income `bank_account_id`.

Pins: `app/controllers/transactions_controller.rb:232-239`, `app/controllers/incomes_controller.rb:65-71`, `test/e2e/web/tenancy_guards_test.rb`

### WEB-TX-05 — Month navigation: out-of-range month clamps by redirect, garbage month resolves to today

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Visit `/transactions?month=2020-01` (history starts 4 full months back — that is the low clamp).
2. Visit `/transactions?month=2099-12` (high clamp is today+12 months).
3. Visit `/transactions?month=banana`.

**Expect:** 2020-01 redirects to the earliest billing month in the ledger; 2099-12 redirects to current month +12; `banana` renders today's month with NO redirect. URL bar shows the clamped `?month=YYYY-MM`.

Pins: `app/controllers/transactions_controller.rb:169-187`

### WEB-TX-06 — Ledger filter sheet: client-side text search and category view

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. On `/transactions` (current month, mixed categories: Mercado, Restaurantes, Transporte, Assinaturas…) type `mercado` into the Movimentos search box.
2. Toggle the category view button.

**Expect:** List filters live to rows whose merchant/category/account text matches; day groups whose rows all filtered out collapse; category view swaps the list for per-category bars whose counts/sums match the visible month; the search box hides in category view (filters target hidden).

**Variants:**
- Search text matching nothing → empty list state, no error.

Pins: `app/javascript/controllers/ledger_controller.js:3-43`, `app/views/transactions/_category_bars.html.erb`

### WEB-TX-07 — Batch transfer modal: all-or-nothing, plus caixinha transfer boosts an active goal

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. For the boost toast, an ACTIVE goal linked to Caixinha must exist — create one at `/goals` first (or skip the boost assertion).
2. Hub hero "Guardar dinheiro" modal: fill Itaú `R$ 100,00` AND Nubank `R$ 50,00`, destination Caixinha → save.
3. Unhappy pass: fill one source with destination BLANK → save.

**Expect:** Two posted transfer rows appear at once; Itaú −100,00, Nubank −50,00, Caixinha +150,00 on derived balances; if a caixinha-linked active goal exists the toast names the boost. Unhappy: 422, NO row saved (all-or-nothing), first error surfaced from `batch_error_message`.

**Variants:**
- Empty modal (no source filled) → `t('transactions.hero.save_modal.none_error')`.
- Source == destination or a card as endpoint → `transfer_shape` validation error, nothing saved.

Pins: `app/controllers/transfers_controller.rb:11-33`, `app/controllers/transfers_controller.rb:54-66`

### WEB-TX-08 — Receipt upload: valid JPG viewable through the authenticated proxy; oversize and fake-type rejected

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Prepare files in scratch: a real small `.jpg`; an 11MB file (`mkfile 11m big.jpg` or `dd`); an `.exe`/text file renamed to `.jpg` (wrong magic bytes).
2. Drawer add expense `R$ 20,00` with the valid jpg attached → save → click the receipt thumb (GET `/transactions/:id/receipt`).
3. Repeat the add with `big.jpg`, then with `renamed.jpg`.
4. Copy the receipt URL into a private (signed-out) window.

**Expect:** Valid jpg posts and renders inline via `send_data` (no public blob URL anywhere in the page source); 11MB → 422 validation error naming the size cap; renamed .exe → 422 (magic-byte probe fails); signed-out receipt URL → redirected to sign-in, bytes never served.

**Variants:**
- Cross-account: another account's session requesting `/transactions/<foreign_id>/receipt` → 404.
- Editing a row while leaving the file field untouched keeps the existing receipt (blank param is NOT a delete — `transactions_controller.rb:204-206`).

Pins: `app/models/transaction.rb:58-60`, `app/models/transaction.rb:191-205`, `app/controllers/transactions_controller.rb:102-113`

### WEB-TX-09 — Confirm a WA-parked row from the pending tray (guarded, double-click safe)

Seed: dev:seed_demo + runner-inserted parked row · AI: deterministic (live-AI alternative)

**Steps:**
1. Insert a parked row deterministically (no AI):
```
bin/rails runner 'u=User.find_by!(email_address:"marina@azulzin.dev"); a=u.account_membership.account; a.transactions.create!(direction:"expense", status:"pending_review", amount_cents:5000, merchant:"Mercado Parked", occurred_on:Date.current, billing_month:Date.current.beginning_of_month, source:"whatsapp", created_by:u)'
```
   (Alternative with live AI: send an ambiguous message from the :3001 simulator on marina's verified JID.)
2. On `/transactions` the "Para revisar" tray shows the card → pick instrument Itaú, click Confirmar.
3. For the race: reload, seed another parked row via the same runner line, and double-click Confirmar fast.

**Expect:** Row leaves the tray, streams into the month ledger as posted `R$ 50,00`; tray badge decrements; edits made on the tray card are saved before confirm (never dropped). Double-click posts exactly ONE row — `guarded_update` makes the second click a no-op.

**Variants:**
- Confirm with an invalid edit (blank amount) → 422, row stays in the tray with errors.
- Parked installment stub (extraction `installments_count` set, credit_card assigned) → Confirmar fans out the full parcel plan instead of one expense (`transactions_controller.rb:88-89, 147-150`).

Pins: `app/controllers/transactions_controller.rb:80-97`, `app/models/transaction.rb:140`, `test/e2e/web/transactions_confirm_test.rb:3`

### WEB-TX-10 — Manual fatura (billing_month) move sticks across later edits

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Add a posted card expense first: `R$ 80,00` crédito on the Nubank card.
2. Edit the card row → change the "Fatura" select to next month → save.
3. Edit again changing only `occurred_on` by one day → save.

**Expect:** First save moves the row's fatura (`billing_month_manual = true`) — the bills tile shifts `R$ 80,00` to the chosen month. Second save does NOT re-derive the fatura (sticky flag survives an occurred_on edit). Changing the instrument, however, resets the flag and recomputes.

**Variants:**
- Fatura select on a bank-account row is ignored (param only applies when `credit_card_id` present).

Pins: `app/controllers/transactions_controller.rb:244-250`, `app/controllers/transactions_controller.rb:222-229`

### WEB-TX-11 — Category backfill (see §8)
Covered in full in §8 (WEB-TX-11 run / WEB-TX-11b undo) using seed 4's pre-seeded uncategorized rows.
### WEB-EXP-12 — Mark this month's expected income received from the hub card

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Sign in as marina; on `/transactions` find the "A receber no mês" card listing Salário Marina (`R$ 6.500,00`, day 5). The demo seed only receives past months + current on day 1 — if already received this month, test in next month via `?month=`.
2. Click Receber (PATCH `/incomes/:id/receive`).

**Expect:** One posted income transaction `R$ 6.500,00` with linked `income_id` lands in the ledger; entradas stays constant (moves from expected to posted) but the Itaú derived balance rises by 650000 centavos; notice `t('incomes.receive.received')` on the HTML fallback.

**Variants:**
- Clicking again for the same month is a no-op (`summary.income_received?` guard) — no duplicate deposit.

Pins: `app/controllers/incomes_controller.rb:49-57`, `config/routes.rb:68`

### WEB-EXP-13 — Incomes CRUD and schedule validations

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. On `/incomes` create an income with (a) blank name; (b) amount `R$ 0,00`; (c) schedule "Todo dia" day 32; (d) "dia útil" day 11.
2. Create a valid one: `Freela`, `R$ 1.200,00`, dia útil 5.
3. Edit it, then delete it from the edit page.

**Expect:** (a)–(d) 422 with inline activerecord errors, Turbo form NOT reset; valid create appends the row; delete soft-deletes with `t('incomes.destroy.removed')` — past receipt transactions keep `income_id`.

Pins: `app/models/income.rb:15-18`, `app/controllers/incomes_controller.rb:14-45`

### WEB-BANK-01 — Bank account create / edit / soft delete with exact derived balance

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. `/bank_accounts` → create via the form: institution Bradesco, nickname `Teste BB`, saldo `R$ 500,00`.
2. Add a `R$ 100,00` debit expense on it in the hub.
3. Return to `/bank_accounts`; then edit → Remover.

**Expect:** List shows derived balance `R$ 400,00` exactly (anchor 50000 − 10000 posted after anchor); blank balance on create anchors `R$ 0,00` (not nil — transfers count from day one); delete redirects with `t('bank_accounts.destroy.removed')` and the account leaves all pickers, while its old ledger rows keep their FK.

Pins: `app/controllers/bank_accounts_controller.rb:13-55`, `app/models/bank_account.rb:40-47`

### WEB-BANK-02 — Editing a bank balance re-anchors: pre-edit rows stop counting

Seed: dev:seed_demo (continues WEB-BANK-01 before its delete step) · AI: deterministic

**Steps:**
1. With `Teste BB` sitting at derived `R$ 400,00` with one −`R$ 100,00` row, open `/bank_accounts/:id/edit` → set saldo to `R$ 1.000,00` → save.
2. Add another `R$ 30,00` expense on it.

**Expect:** Immediately after the edit the derived balance reads exactly `R$ 1.000,00` (the old −100,00 row is behind the new anchor and no longer subtracts); after the new expense it reads `R$ 970,00` — only post-anchor rows count.

Pins: `app/models/bank_account.rb:22-23`, `app/models/bank_account.rb:40-47`, `app/models/bank_account.rb:54-55`

### WEB-BANK-03 — Bank account delete blocked while a kept income deposits into it

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. `/bank_accounts` → edit Itaú (Marina) — the destination of income "Salário Marina" — → Remover.
2. Delete the income at `/incomes` and retry the account delete.

**Expect:** First attempt redirects with the `:has_kept_incomes` activerecord error as alert — account NOT deleted. After removing the dependent income, the same delete succeeds with `t('bank_accounts.destroy.removed')`.

Pins: `app/models/bank_account.rb:27-29`, `app/controllers/bank_accounts_controller.rb:47-55`

### WEB-CARD-01 — Credit card closing math: purchase ON closing day vs day after land in different faturas

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Demo Nubank card: due day 10, closing offset 7 → closes on the 3rd. Add two drawer expenses on that card: `R$ 100,00` dated the 3rd of last month, `R$ 200,00` dated the 4th of last month (use `?month=` navigation so `occurred_on` defaults into that month, then edit dates).
2. Inspect the bills tile on `/transactions` for last month and this month, and the card row on `/dashboard` (open bill + available).

**Expect:** The 3rd-of-month purchase bills in LAST month's fatura; the 4th bills in THIS month's; dashboard "disponível" = limit `R$ 6.500,00` − open bill, exact to the centavo; totals match `bin/rails runner` probes of `open_bill_cents`/`available_cents`.

Pins: `app/models/credit_card.rb:31`, `app/models/credit_card.rb:71-90`, `test/test_helpers/e2e/scenario.rb:140-153`

### WEB-CARD-02 — First billing-config save re-buckets full card history; later saves only open-bill-onward

Seed: dev:seed_demo (plus a new unconfigured card) · AI: deterministic

**Steps:**
1. Create a NEW card WITHOUT `bill_due_day` (leave due day blank) and add 2 card expenses in past months (via `?month=` navigation).
2. `/credit_cards` → edit the new card → set due day 15 / offset 7 → save (first-time config). Note each expense's fatura.
3. Edit again to due day 20 → save.

**Expect:** First save re-buckets ALL history into real faturas (past parcels move); second save only re-derives from the open bill onward — closed historical faturas keep their months. Redirect notice `t('credit_cards.update.updated')`.

Pins: `app/controllers/credit_cards_controller.rb:35-47`, `app/models/credit_card.rb:92`

### WEB-CARD-03 — Card validations and the zero-limit card

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. On the `/credit_cards` form attempt creates with: (a) last4 `abcd`; (b) due day 32; (c) closing offset 29.
2. Create a valid card with limit `R$ 0,00` (or blank) → save, then view it on `/dashboard` and `/credit_cards`.

**Expect:** (a)–(c) 422 with inline errors, Turbo form NOT reset; (d) saves, and the card renders "não informado" for limit/available with NO division error — a limitless card contributes 0 to the dashboard's total available instead of poisoning it.

Pins: `app/models/credit_card.rb:17-23`, `app/models/credit_card.rb:77-90`

### WEB-CARD-04 — Card edit return_path only honors the literal 'transactions' token (open-redirect guard)

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Visit `/credit_cards/:id/edit?return_to=https://evil.example` on any card and save.
2. Repeat with `?return_to=transactions`.

**Expect:** Evil value falls back to `/credit_cards`; `transactions` lands on `/transactions`. Never a redirect off-site.

Pins: `app/controllers/credit_cards_controller.rb:66-70`

### WEB-EXP-14 — Categories: create with rotating color, edit, soft delete keeps ledger label, restore defaults

Seed: dev:seed_demo (≥1 posted expense in 'Lazer') · AI: deterministic

**Steps:**
1. `/categories`: create `Pets` (color pre-picked).
2. Edit its budget to `R$ 200,00`.
3. Delete `Lazer`.
4. Click "restaurar padrões".

**Expect:** Create appends the row (position = max+1); after deleting Lazer it leaves the picker and the categories page, but the existing ledger row still renders the name with the removed-suffix (`category_id` kept); restore re-seeds the pt-BR defaults idempotently (no duplicates of survivors) with `t('categories.restore.restored')`.

**Variants:**
- Blank name or 61-char name → 422 inline error.
- Budget `R$ 0,00` → 422 (`monthly_budget_cents` must be > 0).

Pins: `app/controllers/categories_controller.rb:7-49`, `app/controllers/categories_controller.rb:76-79`, `app/models/category.rb:23-27`

### WEB-EXP-15 — Budget 'sugerir' chip: 3-month median pre-fill, silent under one full month of data

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. `/categories` → edit a seasoned category (4 trailing months exist in the demo seed) → click "sugerir" next to the budget field.
2. Repeat on the brand-new `Pets` category (no history, from WEB-EXP-14).

**Expect:** Seasoned category: field pre-fills with the trailing 3-full-month median as a reais string (deterministic, LLM-free — verify against a runner call to `Budgets::Suggest`). `Pets`: chip stays quiet (204 No Content), field untouched.

Pins: `app/controllers/categories_controller.rb:66-73`, `test/test_helpers/e2e/scenario.rb:105-112`

### WEB-EXP-16 — Create a fixed commitment after its charge day passed; card subscription adopts a matching posted charge

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. For the adoption: first add a posted card expense `Netflix` `R$ 55,90` crédito Nubank dated this bill; today must be past the chosen schedule day (pick day 1).
2. `/commitments` → create fixed `Aluguel` `R$ 1.800,00`, dia 1, instrument Itaú.
3. Create subscription `Netflix` `R$ 55,90`, dia 1, instrument Nubank card.

**Expect:** `Aluguel`'s first occurrence is NEXT month (no retroactive overdue born today). `Netflix` retro-links the existing posted charge (similarity ≥ 0.6 + amount within 20%/R$ 5,00): its occurrence shows PAID this month and the fatura does not double-count (projection replaced by the real row).

**Variants:**
- Direct POST `/commitments` with zero instruments in the account → redirect with `t('shared.needs_instrument.title')`.
- Card installment create with count 0 or parcel `R$ 0,00` → 422 invalid commitment.

Pins: `app/controllers/commitments_controller.rb:117-124`, `app/controllers/commitments_controller.rb:146-160`

### WEB-EXP-17 — Occurrence pay/unpay from hub and commitment page, with amount override and notification dismissal

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. The demo seed has fixed bills with an unpaid occurrence this month. The alert banner requires an unpaid-bill notification — kick the reminder scanner if needed:
```
bin/rails runner 'Reminders::DailyDispatchJob.perform_now'
```
2. Hub "A pagar" zone → Pagar on an occurrence, typing `R$ 5,00` less than scheduled (early-payment discount).
3. On `/commitments/:id` click Desfazer (unpay).
4. If an alert banner shows, pay from the banner button.

**Expect:** Pay posts one transaction for the TYPED amount (override honored, blank keeps schedule), streams into Movimentos, occurrence flips to paid; unpay reverses the payment row and the occurrence returns to due; paying from a banner also dismisses that notification in the same tap (stale `notification_id` silently skips, never blocks).

**Variants:**
- Double-firing pay for the same commitment-month → unique slot: second attempt cannot duplicate the payment.

Pins: `app/controllers/commitment_occurrences_controller.rb:10-33`, `app/controllers/commitment_occurrences_controller.rb:39-51`

### WEB-EXP-18 — Settle (early payoff) and pay_batch guards on installment plans

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Targets from the demo seed: debit installment 6× `R$ 280,00` from Itaú (settle target) and the card installment 10× `R$ 349,90` (guard target).
2. `/commitments/:id` (debit plan) → Quitar with negotiated total `R$ 1.300,00`.
3. Guards: attempt settle on the CARD installment plan; attempt pay_batch with no months selected.

**Expect:** Settle posts ONE transaction of `R$ 1.300,00` and archives the plan (occurrences stop, history kept) with `t('commitments.settle.settled')`. Card-plan settle and empty-month pay_batch redirect with `t('commitments.settle.invalid')` / `t('commitments.pay_batch.invalid')`. Valid pay_batch splits the typed total across the selected months with `t('commitments.pay_batch.paid')`.

**Variants:**
- Settle amount `R$ 0,00` → `.invalid`.
- Commitment delete is a soft delete — payments history survives (`commitments_controller.rb:83-87`).

Pins: `app/controllers/commitments_controller.rb:56-78`, `lib/demo_seed.rb:134-136`

### WEB-DASH-01 — Dashboard tiles tie out: derived balances, open bills, available, pending tray, notifications

Seed: dev:seed_demo (UNTOUCHED) · AI: deterministic

**Steps:**
1. Sign in as marina → `/dashboard` (anchors: Itaú `R$ 3.412,55` + Nubank `R$ 2.148,90` + Caixinha `R$ 5.200,00`, plus any post-anchor rows; limits `R$ 6.500,00` + `R$ 8.000,00`).
2. Cross-check with:
```
bin/rails runner 'a=User.find_by!(email_address:"marina@azulzin.dev").account_membership.account; puts a.bank_accounts.kept.sum{_1.derived_balance_cents.to_i}; puts a.credit_cards.kept.sum{_1.open_bill_cents}'
```

**Expect:** Total balance = sum of derived balances exactly; total fatura = sum of open bills; "disponível" sums per-card available where a limitless card contributes 0; pending tray mirrors the hub; notification banners render dismissible.

Pins: `app/controllers/dashboard_controller.rb:4-18`

### WEB-DASH-02 — Phone-unverified user sees the WhatsApp activation prompt with an AZUL- code

Seed: dev:seed_demo + fresh onboarded teste+4 · AI: deterministic

**Steps:**
1. Visit `/dashboard` as teste+4 (phone set, WhatsApp NOT verified).
2. Visit `/dashboard` as marina (verify her first via the :3001 simulator by sending her code from her JID, or console `user.verify_whatsapp!`).
3. Bonus loop: send the code from the :3001 simulator (JID = user phone `@c.us`) and refresh — needs the fake sidecar but NO AI.

**Expect:** Unverified: activation card shows a code matching `AZUL-[A-Z0-9]{4}` and instructions to send it via WhatsApp. Verified user: no activation card. After the bonus-loop send, the card disappears on refresh.

Pins: `app/controllers/dashboard_controller.rb:5`, `app/controllers/concerns/whatsapp_activation.rb:8`, `app/models/user.rb:157`

### Account settings & LGPD deletion (see §6)
Owner rename vs member denial is §6 MU-EXP-06; ownership transfer is §6 MU-07; the LGPD danger zone is §6 MU-08.
### I18N-02 — Locale switcher is a deliberate no-op while the pt-BR pin holds

Seed: dev:seed_demo · AI: deterministic

**Steps:**
1. Signed in as marina, use the footer/UI language switcher to pick English (PATCH `/locale` `locale=en-US`).
2. Try `?locale=en-US` on `/dashboard`.
3. curl any page with `Accept-Language: en-US`.

**Expect:** `session[:locale]` and `user.locale` DO update (LocalesController whitelists and stores), but every page still renders pt-BR — `resolve_locale` hardcodes `I18n.default_locale` in all envs. **This is the pinned launch behavior; do NOT file it as a bug and do NOT "fix" it** (CLAUDE.md temporary pin). Unsupported locale param (`locale=xx`) is silently ignored, nothing stored.

**Variants:**
- Signed-out visitor uses the switcher → session set, still pt-BR, no error.

Pins: `app/controllers/application_controller.rb:44-58`, `app/controllers/locales_controller.rb:4-11`, `test/e2e/web/i18n_test.rb`
## 6. Multi-user — invites, attribution, LGPD deletion

This chapter proves the whole membership lifecycle: invite issuance/acceptance, the 4-member cap, refusal of data-bearing invitees, per-sender WhatsApp attribution on one shared ledger, member removal/leave, ownership transfer, and LGPD account deletion. It uses **seed 13** (`test-13` solo owner + separate data-bearing invitee `test-13b`) for the invite scenarios and **seed 3** (couple `test-3` + `test-3b`, both WA-verified) for membership and attribution. Seed-3 scenarios mutate membership, ownership, or phone bindings — re-run `bin/rails "exploratory:seed[3]"` wherever a scenario says so. Seed-13 invite scenarios each leave a pending invite behind; the cap counts pending invites, so revoke leftovers on `/account` (or re-seed) between them. Accept links have the shape `http://localhost:3000/invites/<token>`.

### MU-01 — Owner invites a fresh user; token survives signup; empty solo account folds in

Seed: `exploratory:seed[13]` · AI: deterministic

**Steps:**
1. Sign in as `test-13@azulzin.dev` / `test1234` → open `/account`.
2. In the invite form type `novo@example.dev` → submit.
3. The invite email pops in a browser tab automatically (plain letter_opener — there is no /letter_opener web UI; past emails live under `tmp/letter_opener/`). Copy the accept link (`/invites/<token>`).
4. In an incognito window open that link — it redirects to sign-in (the token is stored in the session).
5. Click "Criar conta" → sign up. The email is pre-filled with `novo@example.dev` but editable — the token, not the email, is the credential.
6. Confirm the email via the letter_opener verification link → sign in → the invite confirm page renders → click the join button (POST).

**Expect:**
- After step 2: Turbo-appended pending row, no flash (the Turbo stream only appends the row and clears errors; the `invitations.create.sent` notice appears only on the non-Turbo HTML fallback).
- After step 6: redirect to dashboard with `invitation_acceptances.create.joined` — "Você agora faz parte da conta Teste 13 — Convites/multi-usuário (+ convidado test-13b)."
- `/account` as `test-13` now lists 2 members (`members_count` 1 → 2); the invitee's auto-bootstrapped empty solo account row is destroyed (folded); `invitation.accepted_at` is stamped.

**Variants:**
- Re-click the join button after already joining → idempotent, still redirects with the "joined" flash (accept.rb:13).
- Open the accept link while NOT signed in → the GET only stores the token in session with a 30-min TTL; wait >30 min before signing in and the session copy is treated stale (invitation_acceptances_controller.rb:36-40) — the token carried on the User (`pending_invitation_token`) still joins at first sign-in.

Pins: `app/controllers/invitations_controller.rb:11-25`, `app/controllers/invitation_acceptances_controller.rb:10-26`, `app/services/invitations/accept.rb:9-47`, `app/controllers/registrations_controller.rb:6-31`, `test/e2e/web/multi_user_web_test.rb:29-43`

### MU-EXP-01 — Re-inviting the same email resends (refreshes token); the OLD emailed link dies

Seed: `exploratory:seed[13]` · AI: deterministic

**Steps:**
1. As `test-13` on `/account`, invite `renova@example.dev` → open letter_opener, keep the FIRST email's accept link.
2. Submit `renova@example.dev` in the invite form a second time.
3. Open the FIRST email's accept link in incognito.

**Expect:**
- Step 2 succeeds — `Invitation.issue!` updates the existing open row with a new token + fresh 7-day expiry, no unique-index 500; a second email arrives in letter_opener.
- Step 3: the first link now redirects to sign-in with the generic `invitation_acceptances.show.invalid` — "Este convite não é mais válido." — because the token was regenerated.

**Cleanup:** revoke the pending `renova@` invite on `/account` (pending invites count toward the 4-seat cap).

Pins: `app/models/invitation.rb:30-39`, `app/controllers/invitation_acceptances_controller.rb:29-33`

### MU-02 — Accepting an invite while signed in with a data-bearing account is refused, never silently folded

Seed: `exploratory:seed[13]` · AI: deterministic

Seed 13 ships the invitee ready-made: `test-13b@azulzin.dev` owns its own solo account "Solo do Convidado 13b" holding one expense (R$ 99,00 "Livraria do Convidado") — any of bank_accounts/credit_cards/transactions/commitments/incomes/document_imports makes an account "in use".

**Steps:**
1. As `test-13` on `/account`, invite `test-13b@azulzin.dev`.
2. In a second browser profile sign in as `test-13b@azulzin.dev` / `test1234`.
3. Open the invite link from letter_opener → the confirm page renders (the GET never mutates).
4. Click the join button (POST).

**Expect:**
- Redirect to dashboard with `invitations.errors.account_in_use` — "Sua conta atual já tem dados — não é possível juntá-la a outra."
- `test-13b` keeps her own account untouched (the R$ 99,00 expense is still there); she is NOT added to the seed-13 account; the invitation stays pending (a retry after she empties/deletes her account can still succeed).

**Cleanup:** revoke the pending invite on `/account`.

Pins: `app/services/invitations/accept.rb:17-25`, `app/services/invitations/accept.rb:43-47`, `test/e2e/web/multi_user_web_test.rb:84-95`

### MU-03 — Member cap: pending invites count toward 4; a full account also refuses a still-pending token at accept

Seed: `exploratory:seed[3]` · AI: deterministic

`under_cap` counts `members_count` + OTHER pending invites, so seed 3's 2 members + 2 pending invites = 4 taken.

**Steps:**
1. Sign in as `test-3@azulzin.dev` / `test1234` → `/account`: invite `a@example.dev` (ok), invite `b@example.dev` (ok), then invite `c@example.dev`.
2. Accept `a@` and `b@` via incognito signups (repeat the MU-01 signup dance for each) — the account is now 4/4.
3. Mint one more still-pending token directly (the invite UI refuses new invites once full — the model comment calls the cap a "soft check, UX only"; the accept layer is the hard gate):
```
bin/rails runner "a=User.find_by(email_address:'test-3@azulzin.dev').account; inv=a.invitations.new(email:'late@example.dev', invited_by:a.owner); inv.save!(validate: false); puts inv.token"
```
4. Build the accept link `http://localhost:3000/invites/<printed token>`, open it in a fresh incognito profile, sign up as `late@example.dev`, confirm email, sign in, and click the join button.

**Expect:**
- Step 1, `c@` submit: 422 Turbo re-render of the errors div with the `cap_reached` validation — "Esta conta atingiu o limite de 4 membros." — no row appended.
- Step 4, confirm POST: redirect to dashboard with `invitations.errors.account_full` — "Esta conta atingiu o limite de 4 membros."; `members_count` stays 4; the invitation stays pending so it can be retried after the owner frees a seat.

**Variants:**
- DB backstop: the `CHECK(members_count<=4)` constraint catches any path that skips the app validations — the rescue maps it to `:account_full` (accept.rb:39-40).

**Cleanup:** this fills seed 3 to 4/4 — re-run `bin/rails "exploratory:seed[3]"` before any other seed-3 scenario.

Pins: `app/models/invitation.rb:42-45`, `app/services/invitations/accept.rb:26-41`, `app/models/account_membership.rb:9-15`, `test/e2e/web/multi_user_web_test.rb:47-61`

### MU-EXP-02 — Inviting an existing member is refused inline

Seed: `exploratory:seed[3]` · AI: deterministic

**Steps:**
1. As `test-3` on `/account`, submit `test-3b@azulzin.dev` in the invite form.
2. Also try `TEST-3B@AZULZIN.DEV` — email is normalized downcase.

**Expect:**
- 422 Turbo re-render with the `already_member` validation ("já faz parte desta conta.") in the invite form errors div; no invitation row created, no email sent. Same result for the uppercase variant.

**Variants:**
- Garbage email (`not-an-email`) → format validation error, same errors div.
- 11th invite within an hour → rate_limit kicks: redirect with `shared.rate_limited` (invitations_controller.rb:8-9).

Pins: `app/models/invitation.rb:51-54`, `app/models/invitation.rb:10`

### MU-04 — Expired / revoked / already-used / garbage tokens all give ONE generic message; GET never mutates

Seed: `exploratory:seed[13]` · AI: deterministic

**Steps:**
1. As `test-13` on `/account`, invite `alvo@example.dev`; keep the emailed accept link. Expire it:
```
bin/rails runner "Invitation.open.find_by(email:'alvo@example.dev').update_columns(expires_at: 1.day.ago)"
```
   (a) Open the emailed accept link.
2. (b) Revoked: re-submit `alvo@example.dev` in the invite form (the resend refreshes token + expiry, un-expiring it), then click "revogar" next to it on `/account`, then open the SECOND email's link.
3. (c) Already-used: re-open the consumed link from MU-01 (`novo@`'s) while signed in as a THIRD user.
4. (d) Garbage token: open `http://localhost:3000/invites/NOTAREALTOKEN123`.

**Expect:**
- All four cases: redirect to sign-in with the single generic `invitation_acceptances.show.invalid` — "Este convite não é mais válido." — no distinction leaks which case it was (no enumeration surface). `members_count` unchanged; nothing written on the GET.

**Variants:**
- Race: two browsers holding the SAME forwarded token both confirm — winner joins, loser gets `:invalid` via the under-lock re-check (accept.rb:27-32). Manually: open the confirm page in two incognito profiles signed in as two different fresh users and click both.

Pins: `app/controllers/invitation_acceptances_controller.rb:29-33`, `app/models/invitation.rb:25`, `app/controllers/invitations_controller.rb:27-34`, `test/e2e/web/multi_user_web_test.rb:99-110`

### MU-10 — Direct signup with an email that has a pending invite pauses once: join via link, or knowingly create separate

Seed: `exploratory:seed[13]` · AI: deterministic

**Steps:**
1. As `test-13`, invite `pausa@example.dev`. Do NOT click the email link (no token in any session).
2. Incognito → `http://localhost:3000` → sign-up form → register `pausa@example.dev` directly.
3. On the pause screen, choose the "create a separate account anyway" option (re-submits with `skip_invitation`).

**Expect:**
- Step 2: 422 re-render with a pending-invitation banner offering the choice; the banner NEVER names the inviter or account (no enumeration without the token); no User created yet.
- Step 3: user created with a fresh solo account (`Accounts::Bootstrap`), "check your email" notice; the family invite stays pending and can still be used later via the link.

**Cleanup:** revoke the pending `pausa@` invite on `/account`.

Pins: `app/controllers/registrations_controller.rb:12-31`, `app/controllers/registrations_controller.rb:42-45`

### MU-EXP-03 — Onboarding account-name prompt: owner sees and sets it; an invited member never sees the field

Seed: `exploratory:seed[13]` (member leg continues MU-01) · AI: deterministic

**Steps:**
1. (a) New owner: incognito signup with any fresh email (no invite) → on the onboarding profile step fill name + phone + "Nome da conta" = `Casa Nova` → continue.
2. (b) Invited member: as the MU-01 joiner (`novo@example.dev`, joined but onboarding not finished), open the onboarding profile step. With Brazil (+55) selected, type the NATIONAL number `11955550001` (stored E.164 becomes `5511955550001` — typing the full 55… doubles the dial code). MU-EXP-04 uses it.

**Expect:**
- (a) The new account is renamed to "Casa Nova" (only honored when `account_owner?`).
- (b) The `account_name` field is NOT rendered at all for the member (view guard `<% if account_owner? %>`); the seed-13 account keeps its name. Forging `user[account_name]` in the member's POST is also ignored server-side (`update_owner_account_name` checks `account_owner?`).

**Variants:**
- Owner leaves the field blank → name untouched (`name.present?` guard), no error.

Pins: `app/controllers/onboarding_controller.rb:97-103`, `app/views/onboarding/profile.html.erb:45-51`

### MU-EXP-04 — Multi-phone WA verification: new member activates their own phone with an AZUL- code (deterministic, no AI)

Seed: `exploratory:seed[13]` (continues MU-01 + MU-EXP-03b) · AI: deterministic

The invited member (`novo@example.dev`, phone `5511955550001` set in MU-EXP-03b) sees their AZUL-XXXX code on the onboarding profile step / dashboard activation prompt (WhatsappActivation concern). Read it from the UI or:
```
bin/rails runner "puts User.find_by!(email_address:'novo@example.dev').whatsapp_verification_code!"
```

**Steps:**
1. In the `:3001` simulator click "+ adicionar número" and add `5511955550001` (UI appends `@c.us`).
2. Send `meu codigo AZUL-XXXX` — the code embeds anywhere in the body, case-insensitive.

**Expect:**
- Immediate reply `whatsapp.replies.verified` — "WhatsApp ativado! ✅ Agora é só me mandar seus gastos por aqui."
- `user.phone_verified_at` set, `whatsapp_id` bound to the digits; the dashboard activation prompt disappears (WEB-DASH-02); subsequent captures from this JID attribute to this member on the FAMILY ledger.

**Variants:**
- 9th-digit tolerance: verify with the code sent from JID `551155550001@c.us` (no 9), then capture from `5511955550001@c.us` — `wa_id_candidates` matches both forms (user.rb:201-208).

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:73-86`, `app/models/user.rb:154-187`, `app/views/dashboard/show.html.erb`

### MU-EXP-05 — WA verification denials: already-linked phone, wrong-code guessing cap, unknown-sender throttle

Seed: `exploratory:seed[3]` + `exploratory:seed[13]` · AI: deterministic

**Steps:**
1. (a) phone_already_linked setup — unverify the owner while leaving her `whatsapp_id` (5511910000003) populated, so her JID is unresolvable; then mint a valid code for a user awaiting verification (seed 13's owner is never WA-verified):
```
bin/rails runner "User.find_by(email_address:'test-3@azulzin.dev').update!(phone_verified_at: nil)"
bin/rails runner "puts User.find_by(email_address:'test-13@azulzin.dev').whatsapp_verification_code!"
```
   From JID `5511910000003@c.us` in the simulator, send `meu codigo AZUL-XXXX` with test-13's valid code.
2. (b) Guess cap: from a never-seen JID `5511900000099@c.us` send 11 messages, each containing a WRONG code shape (`AZUL-ZZZ1`, `AZUL-ZZZ2`, … vary the code).
3. (c) Throttle: from another never-seen JID `5511900000088@c.us` send `oi` three times.

**Expect:**
- (a) Reply `whatsapp.replies.phone_already_linked` — "Este número já está vinculado a outra conta no azulzin. Um número só pode pertencer a uma pessoa." — the unique `whatsapp_id` index refuses the double-bind; test-13 stays unverified.
- (b) The first wrong-code messages fall through to ONE unknown-sender reply (throttled); attempts 11+ that day are silently ignored (`CODE_ATTEMPT_CAP` = 10/day/JID).
- (c) Exactly ONE "Número não cadastrado no azulzin." reply; the next messages get silence for 6 hours (per-number cache key).

**Variants:**
- Restarting the Rails server resets the memory_store cache — throttle and cap windows reset (expected in dev, not a bug).

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"` (test-3's verification was removed).

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:71-97`, `app/services/unknown_sender_reply.rb:5-16`, `config/locales/pt-BR.yml:1360-1362`

### MU-EXP-06 — Account rename: owner renames; non-owner is refused on a stale tab

Seed: `exploratory:seed[3]` (fresh) · AI: deterministic

**Steps:**
1. As `test-3` on `/account`, use the rename form → `Casal Renomeado` → save.
2. Stale-tab denial: keep `/account` open as `test-3` in tab A; in tab B run the MU-07 ownership transfer to `test-3b`; back in tab A submit the rename form.

**Expect:**
- Step 1: redirect with `accounts.update.renamed` — "Nome da conta atualizado."
- Step 2: `require_owner!` redirects to `/account` with `accounts.not_owner` — "Só o dono da conta pode fazer isso." — nothing renamed.
- Empty name → alert with the presence validation message.

**Variants:**
- Name >120 chars → length validation alert.

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"` (ownership was transferred in step 2).

Pins: `app/controllers/accounts_controller.rb:15-21`, `app/controllers/concerns/account_ownership.rb`, `app/models/account.rb:26`

### MU-09 — Two phones, one ledger: each member's WA capture is attributed to the sender; both see the household total

Seed: `exploratory:seed[3]` (fresh; both phones WA-verified, seed prints the JIDs) · AI: live-AI (extraction is a real LLM call — only E2E tests stub it)

**Steps:**
1. In the `:3001` simulator pick/add JID `5511910000003@c.us` (test-3) and send `mercado 54,90 no débito itaú`.
2. Pick/add JID `5511920000003@c.us` (test-3b) and send `farmácia 120,30 no débito itaú`.
3. From EACH JID send `como tá o mês?`.

**Expect:**
- Two auto-commit confirmations in the simulator (one per phone).
- Web `/transactions` (signed in as either user) shows BOTH rows on the same ledger with attribution avatars (tooltips "por Teste 3" / "por Teste 3B"); `created_by` matches the sending phone, never the other member.
- Both phones' "como tá o mês?" replies quote the SAME household month total including both captures (sum of both — R$ 175,20 on an otherwise clean month; if other rows exist, both replies must simply be identical).

**Variants:**
- Edit test-3b's row on the web as `test-3` → attribution gains "editado por Teste 3" (Attributable `before_update`, shared/_attribution full mode).
- A THIRD phone (unverified) sending the same text gets the unknown-sender reply and writes nothing.

Pins: `app/services/whatsapp/decider.rb:81`, `app/controllers/api/whatsapp/webhooks_controller.rb:34-66`, `app/views/shared/_attribution.html.erb`, `test/e2e/whatsapp/multi_user_test.rb:6-38`

### MU-06 — Non-owner self-leave keeps the session and mints a fresh solo account; the owner cannot leave

Seed: `exploratory:seed[3]` (fresh) · AI: deterministic

Pre-step: sign in as `test-3b@azulzin.dev` / `test1234` and add one expense via the web form (any value) so he owns attributed rows on the family ledger (MU-09's farmácia capture also works).

**Steps:**
1. Still as `test-3b`, open `/account` → "Sair da conta" → accept the turbo_confirm (`members.destroy.leave_confirm`).
2. Sign in as `test-3` and check `/account` and `/transactions`.
3. Owner variant: as `test-3`, attempt her own leave — the button is hidden for the owner; the guard is server-side, so triggering DELETE on her own membership yields the refusal.

**Expect:**
- Step 1: redirect to dashboard with `members.destroy.left` — "Você saiu da conta." — STILL signed in, now on a fresh empty solo account (different account id, no instruments, dashboard empty).
- Step 2: `/account` shows 1 member; test-3b's old transactions remain on the family ledger with his name ("Teste 3B") in attribution.
- Step 3: redirect to `/account` with `members.destroy.owner_cannot_leave` — "Transfira a posse antes de sair da conta."

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"` (or continue straight into MU-EXP-07 part 2, which uses this exact end state).

Pins: `app/controllers/members_controller.rb:12-28`, `app/services/accounts/remove_member.rb:7-15`, `test/e2e/web/multi_user_web_test.rb:114-128`

### MU-05 — Owner removes a member: signed out EVERYWHERE, fresh solo account minted, attribution display name survives

Seed: `exploratory:seed[3]` (fresh) · AI: deterministic (WA variant needs live AI)

Pre-step: as in MU-06, give `test-3b` at least one attributed row. Keep `test-3b` signed in on a second browser profile with `/transactions` loaded (his open session).

**Steps:**
1. As `test-3` on `/account` → "remover" next to Teste 3B → accept the turbo_confirm (`members.destroy.remove_confirm`, names him).
2. In test-3b's still-open browser, click any link.
3. Sign back in as `test-3b`.
4. As `test-3`, open `/transactions` and hover the attribution avatar on his old rows.

**Expect:**
- Step 1: Turbo removes the member row + count badge refresh (HTML fallback flash `members.destroy.removed` — "Membro removido. Agora ele tem a própria conta vazia.").
- Step 2: the next navigation bounces to sign-in (all his sessions destroyed).
- Step 3: he lands on a fresh empty solo account.
- Step 4: old rows still show "Teste 3B" in the attribution avatar/tooltip (the User survives, display name intact).

**Variants:**
- Post-removal WA behavior (exploratory, uncovered by automation — product gap to watch): test-3b's phone stays WA-verified and bound to his USER — a WA capture he sends after removal lands in his NEW empty solo account (the decider stamps `@msg.user.account`), which has no instruments; observe the degraded/parked reply rather than a silent write to the family ledger (`app/services/whatsapp/decider.rb:81`, `app/controllers/api/whatsapp/webhooks_controller.rb:56`).

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"`.

Pins: `app/controllers/members_controller.rb:19-27`, `app/services/accounts/remove_member.rb:7-15`, `app/views/accounts/_member.html.erb:21-23`, `test/e2e/web/multi_user_web_test.rb:65-80`

### MU-07 — Ownership transfer: old owner demoted, exactly one owner; demoted owner refused on owner routes

Seed: `exploratory:seed[3]` (fresh) · AI: deterministic

**Steps:**
1. As `test-3` on `/account` → "Tornar dono(a)" next to Teste 3B → accept the turbo_confirm (`members.promote.confirm`).
2. Still in test-3's session, try an owner action — e.g. submit the stale invite form or re-click a promote button in a stale tab.

**Expect:**
- Step 1: redirect with `members.promote.promoted` — "Teste 3B agora é dono(a) da conta."; `/account` now shows test-3b as owner, test-3 as member (owner-only controls — invite form, rename, danger zone — disappear for test-3 on reload). The one-owner partial unique index holds throughout (demote-first ordering).
- Step 2: `accounts.not_owner` — "Só o dono da conta pode fazer isso."

**Variants:**
- test-3 (now member) can now self-leave; test-3b (now owner) cannot — re-run MU-06 with roles swapped to confirm the gate follows the role, not the person.

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"`.

Pins: `app/controllers/members_controller.rb:30-35`, `app/services/accounts/transfer_ownership.rb:7-15`, `test/e2e/web/multi_user_web_test.rb:132-145`

### MU-EXP-07 — Attribution display semantics: hidden on solo accounts; "usuário removido" after an ex-member erases their own User

Seed: `exploratory:seed[13]` (part 1) + `exploratory:seed[3]` end-state of MU-06 (part 2) · AI: deterministic

**Steps:**
1. Part 1: sign in as `test-13b@azulzin.dev` / `test1234` (solo account with the R$ 99,00 "Livraria do Convidado" expense) → open `/transactions`.
2. Part 2: run MU-06 first (test-3b self-leaves onto a fresh solo account, his attributed rows stay on the family ledger). Then as `test-3b` open `/account` → "Excluir conta" — this LGPD-deletes his solo account AND his User.
3. As `test-3`, open `/transactions` and hover the attribution avatars on test-3b's old rows.

**Expect:**
- Part 1: NO attribution avatars render at all (the `members_count > 1` guard lives in the partial).
- Part 2: the User destroy nullifies `created_by_id` (FK `on_delete: :nullify`) on the family rows — attribution now shows `shared.attribution.removed_user` ("usuário removido"); the rows and their cents are untouched on the family ledger.

**Cleanup:** destructive to test-3b's User — re-run `bin/rails "exploratory:seed[3]"`.

Pins: `app/views/shared/_attribution.html.erb`, `db/schema.rb:532`, `app/models/concerns/attributable.rb`

### MU-08 — LGPD account deletion: confirm dialog, EVERY member User erased, nobody can sign back in, WA goes unknown-sender

Seed: `exploratory:seed[3]` (fresh — you are about to destroy it) · AI: deterministic

Pre-step: keep `test-3b` signed in on a second browser profile.

**Steps:**
1. As `test-3` on `/account` → danger zone → "Excluir conta" → accept the turbo_confirm (`accounts.show.delete_confirm`).
2. Try to sign in as `test-3@azulzin.dev` AND as `test-3b@azulzin.dev` (test1234).
3. Click around in test-3b's stale session.
4. In the `:3001` simulator send `oi` from JID `5511920000003@c.us` (test-3b's ex-verified phone), then send it again.

**Expect:**
- Step 1: redirect to sign-in with `accounts.destroy.deleted` — "Conta excluída."
- Step 2: both sign-ins fail with the sessions invalid copy — "E-mail ou senha incorretos. Tente novamente." — both User rows are destroyed in the same transaction as the account cascade, so no survivor can mint a fresh solo account.
- Step 3: the stale session bounces to sign-in.
- Step 4: exactly one unknown-sender reply — "Número não cadastrado no azulzin." — then 6h silence per number.

**Variants:**
- Dismiss the confirm dialog → nothing happens (the turbo_confirm is the only confirmation gate — worth eyeballing that the copy is scary enough).
- Non-owner never sees the delete button; direct DELETE as the member → `accounts.not_owner` (before_action `require_owner!`).

**Cleanup:** re-run `bin/rails "exploratory:seed[3]"`.

Pins: `app/controllers/accounts_controller.rb:23-35`, `app/models/account.rb:10-24`, `app/views/accounts/show.html.erb:62`, `app/services/unknown_sender_reply.rb:5-16`, `test/e2e/web/multi_user_web_test.rb:10-25`
## 7. Document imports — extrato/fatura → proposals → apply

This chapter walks the whole document-import pipeline at http://localhost:3000: upload from `/bank_accounts` (or the onboarding wizard), AI extraction with status polling, the review page's confidence-gated checkboxes, apply/discard, dedup, caps, failure modes, and retention. Imports are **web-only** — the :3001 WhatsApp simulator plays no part here. Default seed is `exploratory:seed[11]` (test-11@azulzin.dev / test1234, Itaú conta + Nubank card + caixinha); the couple scenario uses seed 3 and onboarding uses seed 12. Every upload that reaches proposal-building makes one real OpenRouter call (RecurringClassifier — even for CSV/OFX), so run with a live key unless the block says otherwise. **PII rule: never upload anything from `.plans/auto/` — only the synthetic fixtures in `test/fixtures/files/imports/` and files you craft in `/tmp`.**

> **Dedup gotcha when re-testing:** the checksum is over raw bytes, scoped per-account, excluding dismissed/failed imports. To re-run a file, click "Remover" on the old import first (or append a byte to the file).

### WEB-IMP-01 — OFX upload → status polling → review → apply all

Seed: `exploratory:seed[11]` · AI: live-AI

**Steps:**
1. `bin/rails "exploratory:seed[11]"`, then log in at http://localhost:3000 as test-11@azulzin.dev / test1234.
2. Go to `/bank_accounts`. In the uploader, pick `test/fixtures/files/imports/nubank.ofx` ("Escolher arquivos…") and click "Enviar".
3. Watch the status card (it polls every 2s).
4. When the summary appears, click "Revisar e criar" → `/document_imports/review`.
5. Leave everything as pre-checked and click "Criar selecionados".

**Expect:**
- Step 3: spinner + "Lendo o documento…" → summary "%{parts} encontrados" with badge **extrato**; "Revisar e criar" enables.
- Step 4: under **Contas**: Nubank conta ag 1 / 9100349-6, "Saldo R$ 3.576,25", PRE-CHECKED (confidence 0.9 ≥ 0.8 floor). Under **Contas fixas**: "DEBITO AUT. COPEL" pre-checked at R$ 317,41 (deterministic `debito_automatico` signal, floor 0.9). The +5.000,00 credit ("Transferencia recebida") either shows as an UNCHECKED renda with the yellow "conferir" badge (single-month income cap 0.7) or is absent if the live classifier labels it transfer — **never pre-checked**.
- Step 5: flash "N itens criados", redirect to `/bank_accounts`. Verify records:

```
bin/rails runner 'a=BankAccount.find_by(account_number: "9100349-6"); puts [a.balance_cents, a.balance_anchored_at].inspect; c=Commitment.find_by("name ILIKE ?", "%COPEL%"); puts [c.amount_cents, c.source].inspect'
```

`balance_cents=357625`, `balance_anchored_at` = 2026-06-30 end of day; COPEL `amount_cents=31741`, `source="import"`, created_by = the uploader.

**Variants:**
- Upload TWO files at once (nubank.ofx + sample.csv): while either import is non-terminal, the "Revisar e criar" button renders **disabled** (busy guard in `_status.html.erb`).

Pins: `app/controllers/document_imports_controller.rb:80`, `app/jobs/process_document_import_job.rb:41`, `app/services/imports/proposal_builder.rb:107`, `app/services/imports/confidence.rb:20`, `app/services/imports/apply.rb:168`, `app/views/document_imports/_proposal.html.erb:1`, `app/views/document_imports/_status.html.erb:7`

### IMP-EXP-01 — CSV with no account header: identity-less instrument proposes at 0.6, never vanishes

Seed: `exploratory:seed[11]` · AI: live-AI

This is the 3a2899b hardening: a statement with no printed account number must still surface its conta instead of silently dropping it (and everything that depends on it).

**Steps:**
1. From `/bank_accounts`, upload `test/fixtures/files/imports/sample.csv` (Nubank layout `Data,Valor,Identificador,Descrição`, dot-decimal, NO account/bank header → extraction meta = {}).
2. Open `/document_imports/review`.
3. Check the conta proposal, pick the correct institution in its inline select, then "Criar selecionados".

**Expect:**
- Step 2: the bank_account proposal IS built despite no account identity, at confidence 0.6 → arrives **UNCHECKED** with the yellow "conferir" badge; its dependent COPEL fixed-bill proposal survives (references the instrument by pid). Institution defaults from filename fuzzy match: `sample.csv` resolves to **Outro**; rename a copy to `nubank_junho.csv` and re-upload to see **Nubank** resolved.
- Step 3: account created with the institution you edited in.

**Variants:**
- Leave the 0.6 conta UNCHECKED but check its dependent commitment → "Criar selecionados" → the commitment fails with "precisa de uma conta ou cartão que também tenha sido criado." in the some_failed alert (Apply raises MissingInstrument).

Pins: `app/services/imports/proposal_builder.rb:98`, `app/services/imports/proposal_builder.rb:115`, `app/services/imports/proposal_builder.rb:45`, `app/controllers/document_imports_controller.rb:147`, `app/services/imports/apply.rb:71`

### IMP-EXP-02 — Bradesco-style CSV: preamble + split Crédito/Débito columns, "0,00" placeholders

Seed: `exploratory:seed[11]` · AI: live-AI

**Steps:**
1. Craft the synthetic file (NEVER use `.plans/auto` samples — real PII):

```
cat > /tmp/bradesco.csv <<'EOF'
Extrato de: AG 1234 CC 56789-0;;;;
Data;Lançamento;Dcto.;Crédito (R$);Débito (R$)
01/07/2026;DEBITO AUT. VIVO;123;0,00;99,90
05/07/2026;SALARIO ACME LTDA;456;5.500,00;0,00
EOF
```

2. Upload `/tmp/bradesco.csv` from `/bank_accounts`, wait for "encontrados", open `/document_imports/review`.

**Expect:**
- Preamble line is skipped (header detected on line 2 via the KNOWN_HEADER scan); `;` separator detected.
- VIVO row parses as direction OUT, 9990 cents — the filled Débito cell forces OUT; the "0,00" in Crédito is treated as empty, not a debit → shows under **Contas fixas** pre-checked at R$ 99,90, "vence dia 1".
- SALARIO row parses as IN, 550000 cents → renda candidate, UNCHECKED (single-month cap).
- No row silently dropped or double-counted.

Pins: `app/services/imports/csv_parser.rb:32`, `app/services/imports/csv_parser.rb:80`, `app/services/imports/csv_parser.rb:89`, `app/services/imports/format_detector.rb:24`

### WEB-IMP-02 — Fatura PDF (text layer) → card + installment proposals → inline-edit → apply

Seed: `exploratory:seed[11]` · AI: live-AI

Extraction quality here depends on the live model (Gemini via OpenRouter reads the text) — outcomes can vary. The deterministic guarantees are Ruby-side: cents math, the installment-counter regex, dates.

**Steps:**
1. Craft a synthetic fatura: put this text in any editor and print-to-PDF (macOS: Cmd+P → Save as PDF) to `/tmp/fatura.pdf`. **DO NOT** use `.plans/auto/fatura_por_email_santander` (real PII).

```
Banco Santander — Fatura do cartão final 8431
Vencimento: 10/08/2026
Total desta fatura: R$ 1.234,56
Limite: R$ 10.000,00
Período: 05/07/2026 a 04/08/2026
NETFLIX.COM                       44,90
MAGAZINELUIZA Parcela 03/10      150,00
```

2. Upload `/tmp/fatura.pdf` from `/bank_accounts`; wait for the summary (badge **fatura**), open `/document_imports/review`.
3. Before applying: type a new name in the card's inline name field, and — if a renda proposed — a new amount in its `amount_reais` field. Click "Criar selecionados".

**Expect:**
- Step 2: exactly ONE **Cartão** (last4 8431, "vence dia 10") — never one per plastic. MAGAZINELUIZA under **Parcelamentos** with "Parcela 3/10" evidence — the installment_counter signal forces the label regardless of the LLM. NETFLIX under **Assinaturas** (known_subscription).
- Step 3: your edited name/amount win EXACTLY in the created records (edits folded pre-Apply; `Money.to_cents` on the reais string). CreditCard created with `bill_due_day` 10; installment Commitment created with `installments_count` 10, `total_cents` = parcel × 10, `starts_on` walked back 2 months from period end — NO posted parcel transactions.

Pins: `app/controllers/document_imports_controller.rb:147`, `app/services/imports/document_extractor.rb:98`, `app/services/imports/proposal_builder.rb:126`, `app/services/imports/proposal_builder.rb:229`, `app/services/imports/apply.rb:125`, `app/services/imports/apply.rb:184`

### WEB-IMP-03 — Reject one proposal (Descartar), apply the rest

Seed: `exploratory:seed[11]` · AI: live-AI

**Steps:**
1. Fresh state: "Remover" any prior nubank.ofx import, then upload `test/fixtures/files/imports/nubank.ofx` and wait for "encontrados".
2. On `/document_imports/review`, click "Descartar" on the COPEL commitment.
3. Click "Criar selecionados" for the rest.
4. (Second pass) Re-upload after a "Remover" and this time "Descartar" EVERY proposal one by one.

**Expect:**
- Step 2: the discard POSTs `apply` with `discard[pid]`; the proposal flips state=rejected, NO record created, and you STAY on the review page (redirect back to review, not the wizard). The discarded pid is gone from the page.
- Step 3: flash counts only the created items; no COPEL Commitment exists.
- Step 4: after the last discard the import flips to **applied** and its status card shows "✓ Criado — tudo certo" — pinned real behavior; slightly generous copy for an all-rejected import.

Pins: `app/controllers/document_imports_controller.rb:175`, `app/controllers/document_imports_controller.rb:182`, `app/views/document_imports/_import.html.erb:21`

### WEB-IMP-04 — Duplicate checksum: same file refused for member AND spouse; dismissed never blocks

Seed: `exploratory:seed[3]` · AI: live-AI

Seed 3 is the couple: test-3@azulzin.dev + test-3b@azulzin.dev (both test1234) share ONE account — needed to prove dedup is per-ACCOUNT, not per-user.

**Steps:**
1. `bin/rails "exploratory:seed[3]"`, log in as test-3@azulzin.dev, upload `test/fixtures/files/imports/nubank.ofx` from `/bank_accounts`; let it reach any non-failed status.
2. Record the blob count: `bin/rails runner 'puts ActiveStorage::Blob.count'`. Upload the SAME nubank.ofx again as test-3. Re-run the blob count.
3. In an incognito window, log in as test-3b@azulzin.dev and upload the SAME nubank.ofx.
4. Back as test-3, click "Remover" on the original import, then upload nubank.ofx a third time.

**Expect:**
- Steps 2 and 3: flash alert "Você já enviou este arquivo." — no new DocumentImport row, and the blob count is UNCHANGED (checksum computed BEFORE attach, so no orphan blob is written). The spouse hits the same wall: dedupe is per-account.
- Step 4: after dismiss, the re-upload is ACCEPTED and processes normally — dismissed/failed rows are excluded from the uniqueness scope.

Pins: `app/models/document_import.rb:36`, `app/models/document_import.rb:51`, `app/controllers/document_imports_controller.rb:81`, `app/controllers/document_imports_controller.rb:110`

### WEB-IMP-05 — Daily cap: 11th upload refused at controller; job-side race fails rate_limited

Seed: `exploratory:seed[11]` · AI: deterministic (no AI call is ever made)

The cap counts ALL imports created in the last 24h, any status. Dev has no `travel_to` — the 24h window uses the real clock, so seed the 10 rows via runner instead of waiting.

**Steps:**
1. Seed 10 same-day imports without uploading (`save!(validate: false)` with `created_by` set is required — file-presence validation would block a bare row):

```
bin/rails runner 'acc=User.find_by(email_address: "test-11@azulzin.dev").account; u=acc.users.first; 10.times { acc.document_imports.new(checksum: SecureRandom.hex, status: "applied", created_by: u).save!(validate: false) }'
```

2. Controller path: as test-11, upload any file from `/bank_accounts`.
3. Job-race path (bypasses the controller check to hit the in-job re-check):

```
bin/rails runner 'acc=User.find_by(email_address: "test-11@azulzin.dev").account; i=acc.document_imports.new(checksum: SecureRandom.hex, created_by: acc.users.first); i.file.attach(io: File.open("test/fixtures/files/imports/sample.csv"), filename: "s.csv", content_type: "text/csv"); i.save!; ProcessDocumentImportJob.perform_now(i.id)'
```

4. Multi-file edge (optional): reset, seed only 9 rows, then select 2 files in one upload.

**Expect:**
- Step 2: flash "Limite de 10 arquivos por dia atingido. Tente amanhã." — NO record created.
- Step 3: import flips to failed / `error_code=rate_limited` WITHOUT any AI call; its status card on `/bank_accounts` shows "Limite diário de leituras atingido. Tente novamente amanhã." with a "Remover" button.
- Step 4: with 9 existing, a 2-file batch is refused WHOLE (count + incoming > 10).

Pins: `app/controllers/document_imports_controller.rb:13`, `app/controllers/document_imports_controller.rb:97`, `app/jobs/process_document_import_job.rb:46`, `app/jobs/process_document_import_job.rb:95`

### WEB-IMP-06 — Password-protected PDF: wrong password rejected, correct one unlocks, password never persisted

Seed: `exploratory:seed[11]` · AI: live-AI (for the post-unlock extraction)

**Steps:**
1. Encrypt the synthetic statement fixture (needs `brew install qpdf`):

```
qpdf --encrypt senha123 senha123 256 -- test/fixtures/files/imports/statement.pdf /tmp/enc.pdf
```

2. Upload `/tmp/enc.pdf` from `/bank_accounts`; wait for the card to show the password form.
3. Submit the wrong password: `errada`.
4. Submit the correct password: `senha123`.
5. Hygiene check:

```
bin/rails runner 'puts DocumentImport.last.attributes.to_s.include?("senha123")'
```

**Expect:**
- Step 2: import fails with `error_code=password_protected`; card shows "Este PDF tem senha. Digite a senha para desbloquear — usamos só para ler, não guardamos." + inline password field + "Remover".
- Step 3: alert "Senha incorreta. Tente novamente.", card unchanged.
- Step 4: text extracted IN-REQUEST; import resets to uploaded (`error_code` nil) and re-enqueues — spinner returns, then proposals appear.
- Step 5: prints `false` — the password is never stored in DB or job args (the job consumes the pre-extracted pages instead of re-opening the blob).

Pins: `app/controllers/document_imports_controller.rb:32`, `app/jobs/process_document_import_job.rb:88`, `app/services/imports/pdf_text_extractor.rb:21`, `app/views/document_imports/_import.html.erb:24`

### WEB-IMP-07a — Unsupported file type: controller gate (.png) vs magic-bytes gate (png disguised as .csv)

Seed: `exploratory:seed[11]` · AI: deterministic (no AI key needed)

**Steps:**
1. Prepare: `cp test/fixtures/files/imports/sample.png /tmp/fake.csv` and `mkfile 11m /tmp/big.pdf` (or `dd if=/dev/zero of=/tmp/big.pdf bs=1m count=11`).
2. Upload `test/fixtures/files/imports/sample.png` from `/bank_accounts`.
3. Upload `/tmp/fake.csv`.
4. Upload `/tmp/big.pdf`.

**Expect:**
- Step 2: rejected at the controller — flash "sample.png: Tipo de arquivo não aceito", NO DocumentImport row, no job.
- Step 3: PASSES the controller (extension whitelist), but the job's FormatDetector reads magic bytes, finds neither %PDF nor OFX nor csv-like text → import fails with "Não conseguimos ler este tipo de arquivo. Envie PDF, CSV ou OFX." — never stuck at processing.
- Step 4: flash "big.pdf: Arquivo acima de 10 MB", no record (size check fires first at the controller, so the zero-bytes content never matters).

Pins: `app/models/document_import.rb:58`, `app/controllers/document_imports_controller.rb:104`, `app/jobs/process_document_import_job.rb:49`, `app/services/imports/format_detector.rb:9`

### WEB-IMP-07b — AI failure mid-extraction: retries then FAILS visibly — never stuck at "processing"

Seed: `exploratory:seed[11]` · AI: broken-key

**Steps:**
1. Restart the stack with the key poisoned: `OPENROUTER_API_KEY=broken bin/dev-fake` (turning off Wi-Fi works too).
2. Upload `test/fixtures/files/imports/sample.csv` from `/bank_accounts` and watch the status card for ~30–60s (retry_on waits 5s × 3 attempts on the in-process async adapter).
3. Verify: `bin/rails runner 'puts DocumentImport.last.slice(:status, :error_code)'`
4. Recover: restart the stack with the real key, "Remover" the failed import, re-upload the same file.

**Expect:**
- Step 2: card spins "Lendo o documento…" through the retries, then flips to failed with "Algo deu errado na leitura. Tente de novo em instantes." (`llm_failed`) and a "Remover" button. THE core 3a2899b guarantee: retry exhaustion runs `fail_import` — the import must never remain status=processing with an eternal spinner.
- Step 3: `failed` / `llm_failed`.
- Step 4: re-upload is accepted (failed rows don't block the checksum) and now extracts normally.

Pins: `app/jobs/process_document_import_job.rb:17`, `app/jobs/process_document_import_job.rb:33`, `app/jobs/process_document_import_job.rb:58`, `app/services/imports/document_extractor.rb:167`

### WEB-IMP-07c — Parse failures: malformed CSV → parse_failed; 26-page PDF → too_large

Seed: `exploratory:seed[11]` · AI: deterministic (both fail before any LLM call)

**Steps:**
1. Craft the malformed CSV (unclosed quote → `CSV::MalformedCSVError`, the exact bug 3a2899b fixed):

```
printf 'Data,Valor,Descrição\n"broken,01/07/2026\nx' > /tmp/bad.csv
```

2. Upload `/tmp/bad.csv` from `/bank_accounts`.
3. Upload `test/fixtures/files/imports/pages26.pdf` (26 pages > PDF_PAGE_CAP 25).

**Expect:**
- Step 2: import → failed/`parse_failed`, card shows "Não conseguimos ler este documento. Tente outro arquivo ou adicione manualmente." (previously this exception stranded the import at processing forever).
- Step 3: failed/`too_large`, card shows "Arquivo muito grande — o limite é 10 MB." — pinned real copy: it names megabytes even for the PAGE cap. Flagged coverage quirk (product gap), do not "fix" by expecting different copy.
- Both cards offer "Remover".

Pins: `app/services/imports/csv_parser.rb:25`, `app/jobs/process_document_import_job.rb:56`, `app/jobs/process_document_import_job.rb:57`, `app/services/imports/pdf_text_extractor.rb:16`

### IMP-EXP-03 — Scanned/no-text PDF → vision fallback; every proposal capped below the review floor

Seed: `exploratory:seed[11]` · AI: live-AI (import_vision multimodal task)

**Steps:**
1. Build an image-only PDF: screenshot the WEB-IMP-02 synthetic fatura text, then wrap the PNG in a PDF (macOS Preview → File → Export as PDF) to `/tmp/scan.pdf`. Alternative for routing only: `test/fixtures/files/imports/no_text.pdf` (near-blank — the vision model may return nothing, in which case `parse_failed` is also acceptable).
2. Upload the image-only PDF from `/bank_accounts`; wait; open `/document_imports/review`.

**Expect:**
- Text layer unusable → pages rasterized to PNG → vision extraction.
- On review, EVERY proposal — even a fully-identified card — arrives **UNCHECKED** with the "conferir" badge: the vision flag caps confidence at 0.75, below the 0.8 pre-check floor. OCR-grade reads are never auto-trusted.
- Degraded outcome allowed: if the model can't read it, the import must end failed/`parse_failed` or the "nada encontrado" summary — never stuck processing.

Pins: `app/jobs/process_document_import_job.rb:77`, `app/services/imports/document_extractor.rb:111`, `app/services/imports/proposal_builder.rb:30`, `app/services/imports/confidence.rb:11`

### WEB-IMP-08 — Onboarding variant: upload during the accounts wizard step, apply, wizard continues

Seed: `exploratory:seed[12]` · AI: live-AI

Seed 12 is a confirmed user whose wizard has NEVER run — it lands you inside onboarding on first login.

**Steps:**
1. `bin/rails "exploratory:seed[12]"`, log in as test-12@azulzin.dev / test1234 — you are redirected into the wizard. Advance to the accounts step (`/onboarding/accounts`).
2. The page shows the upload hero ABOVE the untouched manual bank-account form. Upload `test/fixtures/files/imports/nubank.ofx`, wait, click "Revisar e criar".
3. Apply all ("Criar selecionados").
4. Click "Continuar".

**Expect:**
- Step 2–3: review renders in the ONBOARDING layout — no app chrome (`resolve_layout` branches on `onboarded?`).
- Step 3: you land back on `/onboarding/accounts` with the created conta in the wizard's list; attribution shows the uploader.
- Step 4: the step's existing gate now passes and "Continuar" advances — zero wizard-machine changes.

Pins: `app/controllers/document_imports_controller.rb:69`, `app/controllers/document_imports_controller.rb:130`, `app/views/onboarding/accounts.html.erb:1`

### WEB-IMP-09 — Reconciler suppresses a cross-account self-transfer income proposal

Seed: `exploratory:seed[11]` · AI: live-AI

**Steps:**
1. Craft the pair: `cp test/fixtures/files/imports/nubank.ofx /tmp/nubank2.ofx`, then edit `/tmp/nubank2.ofx` to be a DIFFERENT account: set `<BANKID>0033`, `<ACCTID>1234567-8`, change every `<FITID>` (append an `X` — this also changes the checksum so dedup won't refuse it), and add inside the `BANKTRANLIST` a matching outbound leg within the ±2-day skew of the original's 04/06 credit:

```
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260605<TRNAMT>-5000.00<FITID>tx999X<MEMO>Transferencia enviada</STMTTRN>
```

2. Upload BOTH `nubank.ofx` and `/tmp/nubank2.ofx` from `/bank_accounts`, wait for both to extract.
3. Open `/document_imports/review` (the Reconciler runs on page load).
4. Deterministic check regardless of AI mood:

```
bin/rails runner 'DocumentImport.awaiting_review.each { |i| i.proposals.each { |p| puts [p["kind"], p["state"]].inspect if p["kind"]=="income" } }'
```

**Expect:**
- IF the classifier proposed the +5.000,00 as a renda, the review page does NOT show it: the paired equal-cents debit (500000) in the OTHER import within ±2 days flips it to rejected before render.
- Step 4: income proposals matching the pair print `state=rejected`.
- Note: if the live classifier already labeled the credit "transfer", no income proposal exists at all — equally correct.

Pins: `app/controllers/document_imports_controller.rb:53`, `app/services/imports/reconciler.rb:18`, `app/services/imports/reconciler.rb:41`

### WEB-IMP-10 — Apply replay-safety + cross-import dedup: two months of the same account create ONE record

Seed: `exploratory:seed[11]` · AI: live-AI

**Steps:**
1. Craft a July copy: `cp test/fixtures/files/imports/nubank.ofx /tmp/nubank_julho.ofx`, then edit it keeping the SAME `<BANKID>0260` / `<ACCTID>9100349-6` (same instrument pid), change `<DTSTART>`/`<DTEND>` to July 2026, change every `<FITID>` (different checksum), and keep a repeat `DEBITO AUT. COPEL` row at the SAME `-317.41` (same commitment pid).
2. Fresh seed 11 state (or "Remover" old imports). Upload BOTH files, wait, open `/document_imports/review`, check everything, click "Criar selecionados" ONCE.
3. Replay: browser Back to the now-stale review page and submit "Criar selecionados" again.
4. Verify:

```
bin/rails runner 'puts BankAccount.where(account_number: "9100349-6").count'
```

**Expect:**
- Step 2: exactly ONE BankAccount 9100349-6 and ONE COPEL Commitment — the shared pid applies once; the later copy binds to the same record (result.skipped, no dup). Flash counts the created items once.
- Step 3: no-op — both imports are status=applied so `awaiting_review` scopes them out; `build_accepted` finds nothing, zero new records, no flash count. Also replay-proof at proposal level: `preload_refs` re-binds via stored GlobalIDs.
- Step 4: prints `1`.

Pins: `app/services/imports/apply.rb:49`, `app/services/imports/apply.rb:87`, `app/services/imports/apply.rb:206`, `app/controllers/document_imports_controller.rb:137`

### IMP-EXP-04 — Remover (dismiss): blob purged, card disappears; other account's import untouchable

Seed: `exploratory:seed[11]` + `exploratory:seed[14]` · AI: live-AI (for the import to exist)

Seed 14 is the tenancy-leak canary — a completely separate solo account (test-14@azulzin.dev / test1234) used here as "the other family".

**Steps:**
1. As test-11, have one live import (any status except applied — e.g. upload sample.csv and don't apply). Note its id N (visible in the card's DOM id, or `bin/rails runner 'puts DocumentImport.last.id'`).
2. Cross-tenant probe FIRST (while the import exists): `bin/rails "exploratory:seed[14]"`, log in as test-14@azulzin.dev in an incognito window, open devtools console on any page and run:

```
fetch('/document_imports/N', {method:'DELETE', headers:{'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content}}).then(r => console.log(r.status))
```

3. As test-11, click "Remover" on the import card.
4. Verify: `bin/rails runner 'i=DocumentImport.find(N); puts [i.status, i.file.attached?].inspect'`

**Expect:**
- Step 2: **404** (RecordNotFound via Current.account scoping) — the other family can never dismiss or unlock it; test-11's card is unaffected.
- Step 3: card vanishes from the status frame (the frame excludes dismissed).
- Step 4: prints `["dismissed", false]` — blob purge enqueued and processed in-process.
- Bonus: the dismissed import stops blocking re-upload of those bytes (WEB-IMP-04 step 4).

Pins: `app/controllers/document_imports_controller.rb:22`, `app/controllers/document_imports_controller.rb:46`, `app/models/document_import.rb:36`

### IMP-EXP-05 — Retention job purges blob + extraction after terminal status; pending reviews survive

Seed: `exploratory:seed[11]` (chained after WEB-IMP-01) · AI: none for the job itself

**Steps:**
1. Preconditions: one APPLIED import (finish WEB-IMP-01) and one EXTRACTED import still awaiting review (upload sample.csv, do NOT apply).
2. The scheduler entry (`config/recurring.yml` `document_import_retention_purge`) does NOT run in dev, and there's no `travel_to` — kick it manually with `retain_days: 0` to skip the 30-day wait:

```
bin/rails runner 'puts DocumentImportRetentionJob.perform_now(retain_days: 0)'
```

3. Revisit `/bank_accounts` and `/document_imports/review`.

**Expect:**
- Step 2: returns 1 (or the count of terminal imports that still had data).
- The APPLIED import loses its blob AND extraction jsonb (`file.attached?` false, `extraction` {}), but keeps checksum/fingerprint/proposals — its status card still renders "✓ Criado — tudo certo" with the fallback "arquivo" filename.
- The EXTRACTED import is untouched — its review is still pending.
- Step 3: nothing user-visible breaks on either page.

Pins: `app/jobs/document_import_retention_job.rb:12`, `config/recurring.yml:24`, `app/views/document_imports/_import.html.erb:6`

### IMP-EXP-06 — No files selected → friendly refusal

Seed: `exploratory:seed[11]` · AI: deterministic

**Steps:**
1. On `/bank_accounts`, click "Enviar" without choosing any file. If the Stimulus pre-check blocks the click, disable JS (devtools → Cmd+Shift+P → "Disable JavaScript") and submit the form with an empty `document_import[files][]`.

**Expect:**
- Redirect back with alert "Selecione ao menos um arquivo para enviar." — no record, no job, no crash on the `params.expect`.

Pins: `app/controllers/document_imports_controller.rb:10`
## 8. Auto-categorization — memory, LLM piggyback, backfill

This chapter exercises ADR 0010 end to end: merchant memory (deterministic, learns ONLY from human-categorized rows), the closed-set LLM piggyback on capture, `category_source` provenance, and the one-click history backfill with banner + undo + 24h cap. Uses seed 1 (warm memory: 3× user-categorized "iFood" → Restaurantes, WA-verified) and seed 4 (6 uncategorized past-month rows built for backfill), plus `dev:seed_demo` for one normalization check. Everything except the raw LLM label is deterministic — each scenario says which half is pinned.

### WA-CAP-01 — WA capture: merchant memory hit categorizes deterministically (source=memory)

Seed: `exploratory:seed[1]` · AI: live-AI (extraction only; the memory step is deterministic)

**Steps:**
1. `bin/rails "exploratory:seed[1]"` — note the printed owner JID `5511910000001@c.us`. Start `bin/dev-fake`.
2. In the simulator at http://localhost:3001, pick `5511910000001@c.us` (or "+ adicionar número" and type the digits) and send: `ifood 45,90`
3. Verify provenance: `bin/rails runner 'puts Transaction.where(merchant: "ifood").order(:id).last.then { |t| [t.amount_cents, t.category&.name, t.category_source].inspect }'`

**Expect:** One posted expense of exactly 4590 cents, category = Restaurantes, `category_source='memory'` (Suggest fires: ≥60% share over the last 20 user-categorized rows for merchant_norm `ifood`). The WA reply names the category — "✅ Lançado: R$ 45,90 no cartão <Instrument> · Restaurantes." (posted_card_categorized / posted_account_categorized) — that named category is the cheap correction loop.

**Variants:**
- Send `guardei 300 na caixinha` — transfer rows stay categoryless by design (scope guard D5; web transfer edits also nil the category).
- Soft-delete Restaurantes first (Categorias page → remove), then send `ifood 30,00` — Suggest only resolves kept categories, so it returns nil and capture falls through to the LLM / uncategorized.

Pins: `app/services/whatsapp/decider.rb:91`, `app/services/categories.rb:8`, `app/services/categories/suggest.rb:13`, `app/services/categories/suggest.rb:18`, `app/models/transaction.rb:163`, `config/locales/pt-BR.yml:1348`

### CAT-EXP-01 — WA capture: memory miss → closed-set LLM piggyback (source=ai)

Seed: `exploratory:seed[1]` · AI: live-AI (twice: extraction AND the label guess)

**Steps:**
1. Same setup as WA-CAP-01. Pick a merchant with zero history in the account.
2. In :3001 send: `droga raia 32,50 no nubank`
3. Check the row: `bin/rails runner 'puts Transaction.order(:id).last.then { |t| [t.merchant, t.amount_cents, t.category&.name, t.category_source].inspect }'`

**Expect:** Posted expense of 3250 cents on the Nubank card. No memory rows exist, so the LLM's category label (the extraction prompt injects the closed-set line of the account's category names) is resolved in Ruby by Resolve — exact-normalized match or trigram ≥0.75 — giving `category_source='ai'`; the reply names it ("… · Saúde."). Repeatability of the label is NOT guaranteed (live AI); what IS pinned: whatever label comes back either resolves to an existing category (source `ai`) or the row posts uncategorized — never an invented category.

**Variants:**
- Obscure merchant + unmappable label, e.g. `25 no zé da esquina`: if the LLM answers category null or a label below 0.75 similarity, the row posts with `category_id` nil / `category_source` nil and the reply uses the plain key "✅ Lançado: R$ 25,00 na conta <X>." (no "· Categoria" suffix).
- Below-confidence park: a vague message that parks still runs auto_assign at build time (the decider upsert is shared) — the parked row in the web review tray already shows the suggested category, and confirming keeps source memory/ai (it only flips to user if the human edits the category).

Pins: `app/services/whatsapp/extractor.rb:103`, `app/services/categories.rb:22`, `app/services/categories/resolve.rb:11`, `app/services/categories/resolve.rb:22`, `app/services/whatsapp/decider.rb:39`, `config/locales/pt-BR.yml:1348`

### WA-CAP-17 — "muda pra X" correction: flips to user provenance and teaches memory

Seed: `exploratory:seed[1]` · AI: live-AI (intent classification only; the flip and the memory chain are deterministic)

**Steps:**
1. Seed 1 setup as above. In :3001 send: `padaria do zé 12,00` (posts, likely uncategorized or ai-categorized — merchant is fresh).
2. Within 24h of that capture (i.e. immediately), send: `muda pra mercado`
3. Chain check — send: `padaria do zé 15,00`

**Expect:** Step 2: the sender's most recent WA row (≤24h, not rejected/superseded, not an installment) gets category = Mercado and `category_source` flips to `'user'` (a spoken correction is human signal). Reply: "✅ Corrigido: R$ 12,00 em <Instrument>." Step 3: the new capture must come back categorized Mercado with `category_source='memory'` — the corrected row now feeds Suggest.

**Variants:**
- `muda pra jardinagem exótica` (no such category, trigram <0.75) → Resolve nil → apply_edit false → reply edit_unclear: "Não entendi a correção. Me diz assim: 'na verdade foi 54,90' — ou ajusta no app." Row unchanged.
- No WA row in the last 24h for this sender (fresh verified user, or wait >24h) → reply nothing_to_edit: "Não achei um lançamento recente pra corrigir."
- Last WA row is an installment parcel (installment_number set) — it is excluded from last_wa_row, so `muda pra X` answers nothing_to_edit instead of touching a parcel.

Pins: `app/services/whatsapp/edit_last_handler.rb:23`, `app/services/whatsapp/edit_last_handler.rb:67`, `config/locales/pt-BR.yml:1380`, `config/locales/pt-BR.yml:1381`, `config/locales/pt-BR.yml:1382`

### CAT-EXP-02 — Web ledger edit: manual category change flips a machine row to user

Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. `bin/rails "exploratory:seed[4]"`, then create one AI-categorized row:
```
bin/rails runner 'a=User.find_by(email_address: "test-4@azulzin.dev").account; a.transactions.create!(merchant: "Loja Zeta", direction: "expense", status: "posted", source: "manual", amount_cents: 5000, occurred_on: Date.current, bank_account: a.bank_accounts.first, category: a.categories.find_by!(name: "Lazer"), category_source: "ai", created_by: a.users.first)'
```
2. Log in at localhost:3000 as test-4@azulzin.dev / test1234, open /transactions, edit the "Loja Zeta" row, change category from Lazer to Vestuário, save.
3. Verify: `bin/rails runner 'puts Transaction.find_by(merchant: "Loja Zeta").category_source'`

**Expect:** `category_source` becomes `'user'` — any manual `category_id` change stamps user (clearing the category instead clears provenance to nil). From now on GET /categories/suggest?merchant=Loja%20Zeta returns Vestuário: memory now sees a user row.

**Variants:**
- Edit the same row's amount only (don't touch category) — `category_source` must NOT change (only `category_id_changed?` triggers the stamp).
- Clear the category to "Sem categoria" — `category_source` goes nil and the row becomes eligible for a future backfill run again (backfill scope is `category_id IS NULL`).

Pins: `app/controllers/transactions_controller.rb:212`, `app/services/categories/suggest.rb:18`, `app/services/categories/backfill.rb:46`

### CAT-EXP-03 — Quick-add merchant-memory preselect (LLM-free) with "sugestão" hint

Seed: `exploratory:seed[1]` · AI: deterministic

**Steps:**
1. Seed 1; log in as test-1@azulzin.dev / test1234.
2. On /transactions open the quick-add entry form, type merchant `iFood`, then tab/blur out of the field (the change event fires GET /categories/suggest?merchant=iFood).
3. Submit the entry with the suggestion left in place, then check: `bin/rails runner 'puts Transaction.where(merchant: "iFood").order(:id).last.category_source'`

**Expect:** The category picker silently preselects Restaurantes and shows the badge "sugestão". Fully deterministic, zero AI. On submit the server stamps `category_source='user'` — the human saw and accepted it; there is deliberately NO silent server-side assignment on quick-add. Submitting with no category leaves `category_source` nil.

**Variants:**
- Pick any category manually FIRST, then type the merchant — the suggestion must never overwrite a touched/filled picker.
- Unknown merchant `Bazar Novo` → endpoint returns 204 No Content → no preselect, no hint.
- Mixed history below the 60% share threshold: seed 2× Mercado + 2× Restaurantes user rows for one merchant —
```
bin/rails runner 'a=User.find_by(email_address: "test-1@azulzin.dev").account; m=a.categories.find_by!(name: "Mercado"); r=a.categories.find_by!(name: "Restaurantes"); [m,m,r,r].each_with_index { |c,i| a.transactions.create!(merchant: "Padoca Mista", direction: "expense", status: "posted", source: "manual", amount_cents: 1000, occurred_on: Date.current - i, bank_account: a.bank_accounts.first, category: c, category_source: "user", created_by: a.users.first) }'
```
  then type `Padoca Mista` → Suggest returns nil → 204, no preselect.
- JS off / offline: form still works, just no preselect (progressive enhancement; fetch errors are swallowed).

Pins: `app/controllers/categories_controller.rb:53`, `app/javascript/controllers/category_suggest_controller.js:29`, `app/views/transactions/_new_entry.html.erb:54`, `app/controllers/transactions_controller.rb:38`, `app/services/categories/suggest.rb:8`

### CAT-EXP-04 — Provenance guard: memory learns ONLY from user rows — machine rows never self-reinforce

Seed: `exploratory:seed[4]` · AI: deterministic

**Steps:**
1. Seed 4, then create 20 identical AI-provenance rows for a fresh merchant:
```
bin/rails runner 'a=User.find_by(email_address: "test-4@azulzin.dev").account; cat=a.categories.find_by!(name: "Lazer"); 20.times { |i| a.transactions.create!(merchant: "Cinema Lux", direction: "expense", status: "posted", source: "manual", amount_cents: 3000, occurred_on: Date.current - i, bank_account: a.bank_accounts.first, category: cat, category_source: "ai", created_by: a.users.first) }'
```
2. Log in as test-4@azulzin.dev and open http://localhost:3000/categories/suggest?merchant=Cinema%20Lux (check status in DevTools Network). Alternatively in :3001 send `cinema lux 30,00` from `5511910000004@c.us`.
3. Now hand-edit ONE of the Cinema Lux rows in /transactions to the same category Lazer (flips it to user) and re-hit the endpoint.

**Expect:** Step 2: 204 No Content / no memory hit — Suggest filters `category_source:'user'` strictly, so 20 unanimous AI rows teach nothing; the WA capture instead re-runs the LLM ladder (source `ai` again if the label resolves). This is the anti-fossilization guarantee of ADR 0010 D3. Step 3: endpoint now returns Lazer (1/1 = 100% share ≥ 60%, sample_size 1).

Pins: `app/services/categories/suggest.rb:18`, `docs/decisions/0010-auto-categorization.md:30`

### WEB-TX-11 — Backfill run: memory pass then closed-set LLM pass, banner with count

Seed: `exploratory:seed[4]` · AI: live-AI (LLM pass; the memory pass is deterministic)

**Steps:**
1. `bin/rails "exploratory:seed[4]"` — it ships 6 uncategorized past-month expenses: 2× "Supermercado E2E" (warm user memory), "Pet Shop Miau"×2, "Farmacia Preco Bom", "Uber Trip" (LLM material).
2. Log in as test-4@azulzin.dev / test1234, visit /categories — the "Categorizar automaticamente" card shows "6 lançamentos sem categoria no seu histórico."
3. Click "Categorizar histórico" (POST /categories/backfill). Deterministic alternative to waiting on the worker:
```
bin/rails runner 'CategorizeHistoryJob.perform_now(User.find_by(email_address: "test-4@azulzin.dev").account.id)'
```
4. Open /transactions and inspect the six rows (Extrato shows the categories; or use the diff runner from CAT-EXP-06).

**Expect:** The POST redirects to /transactions with notice "Estamos categorizando seu histórico — as categorias aparecem no extrato em instantes." After the job: both "Supermercado E2E" rows → Mercado with `category_source='memory'` (free, deterministic); the other 4 go to the batched LLM pass (REAL OpenRouter call in dev — batches of 100, cap 2000 rows/run) and get `category_source='ai'` where the returned label resolves, else stay nil. /transactions shows the banner "N lançamentos categorizados automaticamente." with Desfazer / OK buttons (banner lives 7 days; count computed from the auto_categorized_since window).

**Variants:**
- Broken key (restart with `OPENROUTER_API_KEY=broken bin/dev-fake`) → memory pass still lands (retry_on RateLimited + timeouts, 3 attempts); rows the LLM never answered stay uncategorized — no partial corruption.
- Account with zero categories (see seed 12): closed_set_line returns nil → llm_pass returns 0 silently.
- LLM hallucinates an id or an invented name: batch-local ids (0..99) can at worst hit a sibling row of the same batch, and an unresolvable label is dropped by Resolve — never a cross-account row or an invented category.

Pins: `app/controllers/categories_controller.rb:83`, `app/services/categories/backfill.rb:53`, `app/services/categories/backfill.rb:60`, `app/services/categories/backfill.rb:73`, `app/views/categories/index.html.erb:24`, `app/views/transactions/index.html.erb:45`, `config/locales/pt-BR.yml:655`

### WEB-TX-11b — Backfill undo: reverts exactly the machine-stamped window

Seed: `exploratory:seed[4]` (state from the backfill run above, banner still visible) · AI: live-AI for setup, undo itself deterministic

**Steps:**
1. Run the backfill scenario above; do NOT dismiss the banner.
2. AFTER the run completes: hand-categorize one unrelated row in /transactions (user provenance), AND make one new WA capture that lands a memory category — in :3001 from `5511910000004@c.us` send: `supermercado e2e 25,00` (→ Mercado, source memory).
3. On /transactions click "Desfazer" on the banner (POST /categories/backfill_undo).

**Expect:** Only rows with `category_source IN (memory, ai)` AND `updated_at >= category_backfill_at` AND `created_at < category_backfill_at` revert to `category_id` nil / `category_source` nil. The hand-categorized "user" row keeps its category; the post-run WA capture keeps its "memory" category (created after the stamp, so excluded). `category_backfill_at` is cleared, the banner disappears, notice `categories.backfill.undone`. Undo also RE-ARMS the daily cap — a fresh run is allowed immediately.

**Variants:**
- Click Desfazer twice (double-submit): second POST finds `category_backfill_at` nil → no-op, still redirects with the notice — nothing else reverts.
- Between run and undo, manually edit one backfilled row's category (flips to user) — undo must NOT strip it (source is no longer memory/ai).

Pins: `app/controllers/categories_controller.rb:92`, `app/models/transaction.rb:104`, `app/views/transactions/index.html.erb:50`

### CAT-EXP-05 — Backfill daily cap: controller flash + in-job recheck

Seed: `exploratory:seed[4]` (right after a backfill run; `category_backfill_at` stamped <24h ago) · AI: deterministic

**Steps:**
1. Confirm the stamp: `bin/rails runner 'puts User.find_by(email_address: "test-4@azulzin.dev").account.category_backfill_at'` (should be minutes ago; some rows may still be uncategorized).
2. Visit /categories — the card shows the ran_recently text instead of the button.
3. Force the controller path anyway: replay POST /categories/backfill (curl with your session cookie, or re-submit the form from a stale tab).
4. Separately force the job:
```
bin/rails runner 'CategorizeHistoryJob.perform_now(User.find_by(email_address: "test-4@azulzin.dev").account.id)'
```

**Expect:** Controller: redirect back to /categories with alert "A categorização automática já rodou hoje. Tente de novo amanhã." and no job enqueued. Job: performs but returns immediately at the guard — a duplicate enqueue never buys a second AI run. The stamp is written BEFORE the work, so even a crashed run holds the cap. (No frozen time in dev — the 24h cap runs on wall clock; clear it between attempts with `Account#update!(category_backfill_at: nil)`.)

**Variants:**
- Dismiss quirk (PRODUCT GAP — verify intended): clicking "OK" on the banner clears `category_backfill_at` entirely, which ALSO lifts the 24h cap AND permanently forfeits undo for that run — exploratory check: dismiss, then immediately re-run backfill; it succeeds.

Pins: `app/controllers/categories_controller.rb:84`, `app/jobs/categorize_history_job.rb:18`, `app/jobs/categorize_history_job.rb:20`, `app/controllers/categories_controller.rb:101`, `config/locales/pt-BR.yml:656`

### CAT-EXP-06 — Provenance never overwritten by AI: backfill re-run is a no-op on categorized rows

Seed: `exploratory:seed[4]` (after the backfill run — the account now mixes `user`, `memory`, `ai`, and nil-source rows) · AI: live-AI (re-run may call the LLM on remaining nil rows; the no-overwrite guarantee is deterministic)

**Steps:**
1. Clear the cap: `bin/rails runner 'User.find_by(email_address: "test-4@azulzin.dev").account.update!(category_backfill_at: nil)'`
2. Snapshot before:
```
bin/rails runner 'User.find_by(email_address: "test-4@azulzin.dev").account.transactions.order(:id).each { |t| puts [t.id, t.merchant, t.category&.name, t.category_source].join("\t") }'
```
3. Re-run: `bin/rails runner 'CategorizeHistoryJob.perform_now(User.find_by(email_address: "test-4@azulzin.dev").account.id)'`
4. Run the snapshot again and diff.

**Expect:** Every row that already had ANY category keeps its exact `category_id` and `category_source` — the backfill scope is strictly `category_id IS NULL` and the batch stamp re-checks the scope per id, so a row categorized mid-run (concurrent WA capture or manual edit) is left alone. Only previously-nil rows change. Same guarantee on capture: the Decider only assigns at row-build time; nothing in the AI path ever rewrites an existing category.

**Variants:**
- Parked/pending rows: backfill scope is `.posted` only — a pending_review stub with nil category stays untouched by backfill (it gets its category at capture/confirm time, not from history sweeps).

Pins: `app/services/categories/backfill.rb:46`, `app/services/categories/backfill.rb:86`, `docs/decisions/0010-auto-categorization.md:30`

### CAT-EXP-07 — Installment piggyback: commitment carries the category, parcels stamped at mark-paid

Seed: `exploratory:seed[1]` · AI: live-AI (extraction + label; MarkPaid stamping deterministic)

**Steps:**
1. Seed 1 (Nubank card exists; no history for "Magalu"). In :3001 from `5511910000001@c.us` send: `magalu 10x de 349,90 no nubank`
2. To observe parcel provenance, mark the first parcel paid through the app UI (fatura/commitments screen), or by runner:
```
bin/rails runner 'c=Commitment.find_by(name: "Magalu"); puts Commitments::MarkPaid.call(c, Date.current.beginning_of_month).category_source'
```

**Expect:** Commitment created with `category_id` from the same auto_assign ladder (memory first, LLM label second); reply "✅ Parcelado: 10x de R$ 349,90 em Nubank · <Categoria>. Primeira parcela na fatura de <mês>." when categorized, plain installments_posted otherwise. Parcel transactions do NOT carry provenance at creation — MarkPaid stamps `category_source 'ai'` for whatsapp-sourced commitments and `'user'` for manually created ones; unpaying resets it to nil.

**Variants:**
- Merchant with warm user memory (e.g. an installment for `ifood` on seed 1): commitment category should come from memory, not the LLM — deterministic.
- No resolvable category: `commitment.category_id` nil, reply uses the uncategorized installments_posted key.

Pins: `app/services/whatsapp/installment_decider.rb:70`, `app/services/whatsapp/installment_decider.rb:29`, `app/services/commitments/mark_paid.rb:20`, `app/services/commitments/mark_paid.rb:45`, `config/locales/pt-BR.yml:1371`

### CAT-EXP-08 — TextMatch normalization: accents, case, whitespace fold into one merchant identity

Seed: `dev:seed_demo` · AI: deterministic (endpoint path; WA sends optional/live-AI)

**Steps:**
1. `bin/rails dev:seed_demo` (marina@azulzin.dev / demo1234; "Padaria Estrela" has user-categorized Mercado history). Verify marina's WA phone if you want the WA variant:
```
bin/rails runner 'User.find_by(email_address: "marina@azulzin.dev").verify_whatsapp!("5511999990001@c.us")'
```
2. Log in as marina and hit both spellings (LLM-free): http://localhost:3000/categories/suggest?merchant=PADARIA%20%20ESTRELA and http://localhost:3000/categories/suggest?merchant=padaria%20estréla
3. Optional WA path — in :3001 from `5511999990001@c.us` send `PADARIA   ESTRELA 8,90`, then `padaria estréla 9,50`.

**Expect:** All variants normalize to the same merchant_norm `padaria estrela` (transliterate + downcase + collapse whitespace; stored per row by the before_save hook), so memory fires on every variant → Mercado, source `memory`. The suggest endpoint returns the same `category_id` for every spelling. Note: the trigram (Sørensen–Dice) similarity path only applies to Resolve on LLM labels — merchants match by exact normalized equality only.

**Variants:**
- Blank/whitespace-only merchant → TextMatch.normalize → nil presence → Suggest returns nil instantly (no query).
- A NEAR-miss merchant name ("Padaria Estrelar") is a different merchant_norm → memory MISS by design (no fuzzy merchant matching) — falls to the LLM.

Pins: `app/models/text_match.rb:5`, `app/models/text_match.rb:11`, `app/models/transaction.rb:163`, `app/services/categories/suggest.rb:14`
## 9. Cross-cutting — tenancy, errors, mobile, retention, admin

This chapter sweeps everything that lives between features: the admin/WhatsApp connection lifecycle, webhook edge auth, data retention, export tenancy (the leak canary), auth/session/OAuth/allowlist gates, error pages, the mobile viewport pass, and the deterministic "make the AI fail" trigger. Seeds: mostly `dev:seed_demo` (marina/rafael), plus `exploratory:seed[14]` (tenancy canary), `exploratory:seed[5]` (consent opt-in), and `exploratory:seed[12]` (onboarding gate). Remember: in dev NOTHING recurring fires — every sweep below is kicked with an explicit runner.

### WEB-ADM-01 — Admin WhatsApp connection panel: QR / disconnect / auth_failed lifecycle

Seed: `dev:seed_demo` · AI: deterministic

The fake sidecar self-announces "connected" and never emits lifecycle events — you curl them into the webhook yourself.

**Steps:**
1. Grant marina admin (no UI exists for this):
   ```
   bin/rails runner 'User.find_by!(email_address:"marina@azulzin.dev").update!(admin: true)'
   ```
2. With `bin/dev-fake` running, sign in as marina@azulzin.dev / demo1234 and open http://localhost:3000/admin/whatsapp_connection. Keep the tab visible.
3. Drive each lifecycle event with curl, watching the panel between each:
   ```
   curl -s localhost:3000/api/whatsapp/webhook -H 'Authorization: Bearer dev-whatsapp-token' -H 'Content-Type: application/json' -d '{"event":"qr_code","data":{"qr_data_url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="}}'
   ```
   Then repeat the same curl with each payload in turn: `{"event":"disconnected","data":{"reason":"phone offline"}}` → `{"event":"auth_failed","data":{"error":"bad session"}}` → `{"event":"connected","data":{}}` → `{"event":"logged_out"}`.
4. Click the panel's "Reconectar" button, then the "Encerrar sessão" (logout) button.

**Expect:** The QR image renders on the panel and status flips live over ActionCable — no page reload — through qr → disconnected (with "phone offline" in last_error) → auth_failed → connected → logged_out. "Reconectar" POSTs `/session/initialize` on the sidecar and flashes `t('.initializing')`; "Encerrar sessão" flashes `t('.logged_out')` and status becomes logged_out.

**Variants:**
- Non-admin rafael visits /admin/whatsapp_connection → redirected to /dashboard with the `admin.not_authorized` alert.
- Kill the sidecar process, then click "Reconectar" → rescue path: alert `t('.failed')`, status 'disconnected', last_error set.

Pins: `app/controllers/admin/base_controller.rb:8`, `app/controllers/admin/whatsapp_connections_controller.rb:6`, `app/controllers/api/whatsapp/webhooks_controller.rb:10`, `app/models/whatsapp_connection.rb:1`

### WEB-ADM-02 — Sidecar health-check badge (30s schedule is production-only)

Seed: `dev:seed_demo` (marina admin, per WEB-ADM-01 step 1) · AI: deterministic

Dev cache is `:memory_store` per process, so a `bin/rails runner` cache write is invisible to the server — the panel's `service_up?` falls back to a LIVE probe when the cache is cold, which is exactly the dev path.

**Steps:**
1. With the sidecar up, load /admin/whatsapp_connection → note the "up" badge (live-probe fallback).
2. Kill ONLY the sidecar, leaving Rails running: `pkill -f 'node fake.js'`. Reload the panel.
3. Restart the sidecar (via foreman, or directly: `cd whatsapp-sidecar && PORT=3001 RAILS_WEBHOOK_URL=http://localhost:3000/api/whatsapp/webhook RAILS_API_TOKEN=dev-whatsapp-token node fake.js`), reload again.
4. Optional job-path check: run `WhatsappServiceHealthCheckJob.perform_now` from the WEB CONSOLE (in-process), not `bin/rails runner` — a runner's cache write never reaches the server.

**Expect:** Badge reads down while fake.js is dead, up after restart; no exception when the probe fails (health_check returns falsy). The ActionCable broadcast-on-flip only fires from the scheduled job (prod) — in dev the badge updates on reload. Pin that as the real dev behavior.

**Variants:**
- Sidecar dead + badge down while the NT-G-05 runner marks the connection disconnected: notification pushes stay dashboard-only — cross-check that the two states are independent (cache badge vs `WhatsappConnection.status`).

Pins: `app/jobs/whatsapp_service_health_check_job.rb:14`, `app/controllers/admin/whatsapp_connections_controller.rb:40`, `config/recurring.yml:16`

### X-EXP-01 — Retention job purges old media + transcripts but spares a blob shared with a receipt

Seed: `dev:seed_demo` · AI: live-AI (the two prerequisite captures)

**Steps:**
1. From marina's chat in the http://localhost:3001 simulator, create two inbound messages that must exist BEFORE the run:
   (a) record a voice note that produces a transaction (e.g. speak "padaria quinze reais") — the transcription is stored on the WhatsappMessage;
   (b) upload a receipt image that posts a transaction WITH the receipt attached (WA-CAP-24 — the receipt copies the SAME blob).
2. Run the retention job with the wait skipped (`retain_days: 0` replaces the 60-day cutoff):
   ```
   bin/rails runner 'puts WhatsappRetentionJob.perform_now(retain_days: 0)'
   ```
3. Check /admin/whatsapp_messages (as admin marina) and the transaction's receipt page.

**Expect:** The runner prints the purged count. Voice message: media blob purged AND transcription nil'd (`update_columns`), but the WhatsappMessage row and its transaction survive. Receipt message: the WA attachment is DETACHED (not purged) because the blob is shared — `/transactions/:id/receipt` still serves the image afterwards. The admin audit page shows both rows now media-less.

**Variants:**
- Run it twice — the second run purges 0 (idempotent, "had" guard).
- A message younger than the cutoff (default run, no `retain_days`) keeps media + transcript.

Pins: `app/jobs/whatsapp_retention_job.rb:12`, `app/jobs/whatsapp_retention_job.rb:31`, `config/recurring.yml:20`

### WEB-ADM-03 — Admin inbound-message audit trail

Seed: `dev:seed_demo` (marina admin) · AI: live-AI (prerequisite captures only)

**Steps:**
1. Ensure at least one text, one audio, and one image capture have been sent through the :3001 simulator (reuse WA-CAP-01/21/24 leftovers, or the X-EXP-01 captures above).
2. As admin marina, visit http://localhost:3000/admin/whatsapp_messages.
3. Click into one audio row and one image row (`/admin/whatsapp_messages/:id`).

**Expect:** Index lists the last 100 inbound messages newest-first with user/account. The show page renders the voice-note audio player / receipt thumbnail via Active Storage, the stored transcription, the `ai_result` JSON, and links the produced transaction(s).

**Variants:**
- Non-admin rafael on /admin/whatsapp_messages → dashboard redirect + `admin.not_authorized` alert.

Pins: `app/controllers/admin/whatsapp_messages_controller.rb:5`, `app/views/admin/whatsapp_messages/index.html.erb:1`

### X-EXP-02 — Webhook edge auth: wrong bearer 401s, unknown event is a logged no-op 200

Seed: none (bin/dev-fake running) · AI: deterministic

**Steps:**
1. Wrong token:
   ```
   curl -si localhost:3000/api/whatsapp/webhook -H 'Authorization: Bearer WRONG' -H 'Content-Type: application/json' -d '{"event":"message_received","data":{"from":"5511987654321@c.us","message_id_serialized":"authfail_1","type":"text","body":"mercado 10"}}'
   ```
2. Same curl with the `Authorization` header removed entirely.
3. Correct token (`Bearer dev-whatsapp-token`) but body `'{"event":"banana"}'`.
4. Check `log/development.log` and `bin/rails runner 'puts WhatsappMessage.where(wa_message_id: "authfail_1").count'`.

**Expect:** (1)+(2) HTTP 401, NO WhatsappMessage row created, no job enqueued. (3) HTTP 200 with `Unknown WhatsApp event: banana` warned in log/development.log; nothing persisted. Deterministic, zero AI.

Pins: `app/controllers/api/whatsapp/webhooks_controller.rb:28`, `app/controllers/api/whatsapp/webhooks_controller.rb:18`

### WA-CAP-29 — move_bill: "joga pra próxima fatura" moves the last WA card purchase, sticky manual override

Seed: `dev:seed_demo` · AI: live-AI (intent + target-month words; the month math is deterministic)

**Steps:**
1. Verify marina's Nubank card HAS billing config (due day 15 / offset 7) — check the instrument settings on /bank_accounts and set it if missing.
2. From marina's chat in the simulator, capture a simple card purchase first: `padaria 30 no nubank`.
3. Then send: `joga essa compra pra próxima fatura`.
4. On /transactions confirm which fatura bucket the row landed in.
5. In the web hub, edit that row's `occurred_on` by one day (WEB-TX-10 style) and re-check the fatura bucket.

**Expect:** A `bill_moved` reply naming the amount, merchant and the target month; a bare "outra fatura" defaults to billing_month+1 (move means move). The row gets `billing_month_manual=true`, so the later `occurred_on` edit does NOT re-bucket it — the manual fatura sticks.

**Variants:**
- Last WA row is a débito purchase → `move_not_card` reply, nothing changed.
- No WA row in the last 24h (or the last one was an installment parcel) → `nothing_to_move` reply.

Pins: `app/services/whatsapp/move_bill_handler.rb:14`, `app/services/whatsapp/interpreter.rb:52`, `.plans/e2e/07-coverage-audit.md:89`

### X-EXP-12 — edit_last: merchant / instrument / date corrections (extends WA-CAP-16, §2)

Seed: `dev:seed_demo` · AI: live-AI (edit_field_hint comes from extraction)

Marina needs Itaú (debit) + a configured Nubank card. The catalog only covers amount + category corrections; this pins the other three fields.

**Steps:**
1. Capture: `mercado 54,90 no débito no itaú` — then send `na verdade foi na Padaria Estrela`.
2. Fresh capture (same message) — then send `foi no nubank, não no itaú`.
3. Fresh capture — then send `isso foi ontem`.
4. After (2), open /transactions and find the row.

**Expect:** Each correction returns the "edited" reply with amount + instrument display name. (2) runs `assign_instrument!` → billing_month recomputes onto the Nubank fatura — verify on /transactions the row moved to the faturas bucket. (3) `occurred_on` moves one day back and, on a card row, may re-bucket the fatura via callbacks.

**Variants:**
- Correction sent >24h after the capture — age the row first:
  ```
  bin/rails runner 'Transaction.order(:id).last.update_columns(created_at: 25.hours.ago)'
  ```
  → `nothing_to_edit` reply.
- Un-actionable correction (`muda aí`) → `edit_unclear` reply, row untouched.

Pins: `app/services/whatsapp/edit_last_handler.rb:33`, `app/services/whatsapp/edit_last_handler.rb:50`, `.plans/e2e/07-coverage-audit.md:91`

### X-EXP-13 — Export tenancy: another account's rows NEVER appear in any format

Seed: `dev:seed_demo` + `exploratory:seed[14]` · AI: deterministic

The roadmap's named-scariest #2. Seed 14 plants the canary: a separate solo account whose ONE expense is R$ 666,66 "VAZAMENTO LTDA" — leak checks become a grep, not an eyeball.

**Steps:**
1. Run `bin/rails "exploratory:seed[14]"` so the canary account exists alongside the demo household. Rafael should have his own WA-captured rows in the demo account (send one from his simulator chat if needed).
2. Signed in as marina, download all three: http://localhost:3000/exports.csv?preset=all, /exports.xlsx?preset=all and /exports.pdf?preset=all.
3. `grep VAZAMENTO` the CSV; open the xlsx and pdf and eyeball for the R$ 666,66 row.
4. Cross-foot: compare the CSV's cent totals against the /transactions month summary.
5. Sign in as test-14@azulzin.dev / test1234 and download the same preset.

**Expect:** "VAZAMENTO LTDA" appears in NONE of marina's three files; rafael's rows DO appear in marina's export (account-scoped, not user-scoped) with attribution intact. CSV cent totals tie out exactly to the /transactions month summary.

**Variants:**
- Signed in as the canary owner (test-14), the same preset shows ONLY the one 666,66 row.

Pins: `app/controllers/exports_controller.rb:12`, `.plans/e2e/07-coverage-audit.md:51`

### I18N-03 — Mailer pt-BR pin: en-US recipient still gets pt-BR emails (deliberate launch pin)

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Store an en-US locale on rafael:
   ```
   bin/rails runner 'User.find_by!(email_address:"rafael@azulzin.dev").update!(locale: "en-US")'
   ```
2. Visit /passwords/new, submit rafael@azulzin.dev → letter_opener opens the reset email in a browser tab.
3. Also trigger an invite email to an en-US-localed address (MU-01 flow) and a fresh signup verification email.

**Expect:** Subject AND body are pt-BR despite `user.locale = "en-US"` — `ApplicationMailer#set_locale` hardcodes `I18n.default_locale` (the commented-out recipient-locale line at application_mailer.rb:10 is the post-pin contract). **Product gap, deliberate:** pin this as REAL behavior; the expectation flips when the launch pin lifts. Do NOT "fix" the pin in passing.

Pins: `app/mailers/application_mailer.rb:11`, `.plans/e2e/07-coverage-audit.md:84`

### X-EXP-03 — Logout and session lifecycle: Sair destroys the session, back-button cannot resurrect it

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Sign in as marina, browse to /transactions, click "Sair" (DELETE /session).
2. Press the browser Back button, then force-refresh.
3. From the cached page, retry any in-app POST (e.g. re-submit the drawer form).
4. Verify the session row is gone:
   ```
   bin/rails runner 'puts Session.where(user: User.find_by!(email_address:"marina@azulzin.dev")).count'
   ```

**Expect:** 303 redirect to /session/new on logout. Back may paint a cached page, but any refresh or navigation bounces to sign-in, and the stale POST is rejected (no row created). The runner prints 0 for that browser's session.

**Variants:**
- Two browsers signed in → logout in one leaves the other alive (per-session destroy, unlike the WEB-AUTH-05 reset-all).

Pins: `app/controllers/sessions_controller.rb:22`, `app/models/session.rb:1`

### X-EXP-04 — Google OAuth: fresh solo account, invited-signup skip, failure redirect

Seed: none (demo optional) · AI: deterministic

Requires Google client_id/client_secret in Rails credentials (`dig(:google,...)`) — WITHOUT them only the failure path is testable. Use a real Google account not yet registered.

**Steps:**
1. On /session/new click "Continuar com o Google" and complete consent.
2. Invited variant: open an MU-01 invite link first (token lands in session), THEN do the Google flow.
3. Failure path (deterministic, no creds needed): visit http://localhost:3000/auth/failure?message=access_denied directly.

**Expect:** Fresh OAuth user: signed in with the `omniauth.signed_in` notice, owns a NEW solo account, lands in onboarding (member never sees the account-name field, per the invited variant). Invited variant: `skip_account_bootstrap` — joins via the confirm page, no orphan solo account minted. Failure: redirect to /session/new with the `omniauth.failure` alert.

**Variants:**
- Google email matching an EXISTING password user — verify whether it links (oauth_identity) or refuses; **pin the real behavior** (unpinned in the map).
- In prod the allowlist validation also gates OAuth signup (`user.rb:48`, on: :create) — `could_not_sign_in` alert.

Pins: `app/controllers/omniauth_callbacks_controller.rb:6`, `app/models/user.rb:128`, `config/initializers/omniauth.rb:2`, `config/routes.rb:38`

### X-EXP-05 — Signup allowlist gate (prod pin): non-allowlisted email cannot create a User anywhere

Seed: `dev:seed_demo` · AI: deterministic

The allowlist is prod-only config; the dev repro is a TEMPORARY development.rb edit. **Revert it when done.**

**Steps:**
1. Add to `config/environments/development.rb`: `config.x.allowed_emails = %w[marina@azulzin.dev]` — restart `bin/dev-fake`.
2. (a) /registration/new signup as bloqueado@example.dev.
3. (b) As marina, issue an invite to bloqueado@example.dev and walk the accept-signup in an incognito window.
4. (c) Sign in as marina normally.
5. Verify no user was minted:
   ```
   bin/rails runner 'puts User.exists?(email_address: "bloqueado@example.dev")'
   ```
6. **REVERT the development.rb edit and restart.**

**Expect:** (a)+(b) refused with the allowlist validation error rendered on the signup form; the runner prints false. (c) unaffected — the validation is on: :create only, existing users sign in fine. Documents how the launch gate actually behaves before it is lifted.

Pins: `app/models/user.rb:45`, `app/models/user.rb:212`, `config/environments/production.rb:89`

### X-EXP-06 — Marketing landing + host-aware robots.txt + signed-in redirect

Seed: `dev:seed_demo` · AI: deterministic

**Steps:**
1. Signed out: open http://localhost:3000/ → landing.
2. Sign in as marina, visit / again.
3. Compare robots by host:
   ```
   curl -s localhost:3000/robots.txt
   curl -s localhost:3000/robots.txt -H "Host: app.localhost"
```
   `config.x.app_host` is nil in dev, so BOTH return the crawlable variant. To exercise the app-host branch, temporarily add `config.x.app_host = "app.localhost"` to `config/environments/development.rb`, restart, re-run — then REVERT.

**Expect:** (1) The "azulzinho"/"no azul" brand-voice landing with real-UI replica sections, all pt-BR keys. (2) Redirect to /dashboard — in dev `on_app_host?` is unconditionally true (`!Rails.env.production? || …`, application_controller.rb:34-36), so a signed-in `/` ALWAYS redirects locally; the host check only bites in prod. (3) Marketing host: `Disallow:` (crawlable); app host: `Disallow: /`.

Pins: `app/controllers/pages_controller.rb:6`, `app/controllers/pages_controller.rb:14`, `config/routes.rb:14`

### X-EXP-07 — Error pages: branded static 400/404/422/500 + the modern-browser 406 gate

Seed: none · AI: deterministic

**Steps:**
1. Open each static page directly: localhost:3000/404.html, /422.html, /500.html, /400.html, /406-unsupported-browser.html.
2. Dynamic 406 with an ancient UA rejected by `allow_browser versions: :modern`:
   ```
   curl -si localhost:3000/session/new -A 'Mozilla/5.0 (Windows NT 6.1; rv:11.0) like Gecko'
   ```
3. Note on dynamic 404s: in dev, /transactions/999999 renders the debug page (`consider_all_requests_local`) — the static pages ARE what prod users see.

**Expect:** All five static pages render branded, mobile-safe, pt-BR copy (no raw Rails default). The ancient-UA request gets HTTP 406 with the unsupported-browser page.

Pins: `public/404.html:1`, `public/406-unsupported-browser.html:1`, `app/controllers/application_controller.rb:24`

### X-EXP-08 — Onboarding gate: un-onboarded user deep-linking ANY app page is bounced to the wizard

Seed: `exploratory:seed[12]` · AI: deterministic

Seed 12 gives exactly the state needed: test-12@azulzin.dev confirmed + account bootstrapped but the wizard NEVER run. (Alternatively, stop right after the profile step of WEB-ONB-01.)

**Steps:**
1. Sign in as test-12@azulzin.dev / test1234.
2. Type each URL directly: /transactions, /dashboard, /goals, /account, /categories, /notification_preferences, /exports/new.

**Expect:** Every one redirects to /onboarding; the wizard resumes at the correct incomplete step. The gate is NOT a single shared before_action: most app controllers inherit it from AppController, but TransactionsController, AccountsController and CategoriesController inherit ApplicationController and declare their own `require_onboarding` — and only for some actions (accounts gates only `:show`, categories only `:index`). Exploratory: probe the UNgated actions of those three controllers (e.g. POST /categories, other /account member actions) as an un-onboarded user and flag anything reachable as a gap.

**Variants:**
- POST attempts (e.g. curl POST /transactions with the browser's session cookie) are equally bounced, not just GETs.

Pins: `app/controllers/app_controller.rb:5`, `app/controllers/transactions_controller.rb:8`, `app/controllers/accounts_controller.rb:6`, `app/controllers/categories_controller.rb:5`

### X-EXP-09 — Mobile viewport pass: bottom sheets, dashboard tiles, goal page, PWA manifest at real phone width

Seed: `dev:seed_demo` · AI: deterministic

Use a REAL browser's devtools device toolbar at 390x844 — headless Chrome clamps to 500px, so this is exactly what automation cannot cover.

**Steps:**
1. At 390px width, signed in as marina, walk: /dashboard (tiles + alert banner), /transactions ('Adicionar' drawer, filter sheet, pending tray card, 'Guardar dinheiro' modal), /goals/:id (plan cards + replan buttons), /notification_preferences (toggles).
2. GET localhost:3000/manifest.json and check the Chrome install-app prompt.

**Expect:** The daisyUI bottom modals open as full-width bottom sheets — NOT corner-pinned (the `place-items:end` + `max-w` gotcha); no horizontal page scroll anywhere; tap targets usable; the manifest serves the azulzin icons/name.

**Variants:**
- Rotate to landscape 844x390 — drawer and month summary still usable.
- iOS Safari (real device or simulator): safe-area insets don't clip the bottom-sheet buttons.

Pins: `config/routes.rb:27`, `app/views/transactions/index.html.erb:1`

### X-EXP-10 — Turbo-fetched picker fragments keep picked values across débito/crédito toggles

Seed: `dev:seed_demo` · AI: deterministic

Regression guard for the noscript/DOMParser bug: a noscript fallback inside a Turbo-fetched fragment became a live duplicate field and blanked picked values.

**Steps:**
1. As marina (Itaú debit + configured Nubank card + categories) open 'Adicionar' on /transactions.
2. Pick category 'Mercado', pick instrument Itaú.
3. Toggle payment kind débito → crédito → débito — each toggle Turbo-fetches the instrument picker fragment. **After every toggle, assert the picker button still displays the picked value before the next action** (browser-lane discipline).
4. Fill R$ 12,34 and submit.

**Expect:** After every toggle the picker button still DISPLAYS the picked value and the hidden field still carries it — the row posts with category Mercado + instrument Itaú, R$ 12,34.

**Variants:**
- Same dance inside the onboarding accounts step and the goal-draft caixinha picker — any Turbo-refreshed fragment containing a picker.

Pins: `app/views/transactions/_form.html.erb:1`

### NT-R-06 — Reminder lead-day EXTREMES: 0 = only day-of, 7 = a week out

Seed: `dev:seed_demo` (plus two hand-made commitments) · AI: deterministic

The catalog tests the bounds validation but not the window behavior at the extremes.

**Steps:**
1. Give marina two fixed commitments in the web hub: 'Condomínio' R$ 850,00 with its next occurrence due exactly 7 days from today, and 'Internet' R$ 99,90 due today. Verify the due dates on screen.
2. On /notification_preferences set 'avisar com antecedência' = 0, save, then run:
   ```
   bin/rails runner 'u=User.find_by!(email_address:"marina@azulzin.dev"); Reminders::NotifyMemberJob.perform_now(u.account.id, u.id)'
   ```
3. Check the in-app Notification rows (bell / dashboard).
4. Clear between passes: `bin/rails runner 'Notification.where(kind: "bill_due").delete_all'` — then set lead days to 7, save, and re-run the same runner.

**Expect:** lead_days=0: only the due-TODAY Internet bill notifies; the 7-days-out Condomínio is silent. lead_days=7: Condomínio fires a week ahead with its exact cents (R$ 850,00) in the pt-BR body. Window respected at both extremes, no off-by-one.

Pins: `.plans/e2e/04-notification-trust-suite.md:43`, `app/jobs/reminders/notify_member_job.rb:1`

### X-EXP-11 — WhatsApp consent OPT-IN: the toggle the whole notification catalog presumes already on

Seed: `exploratory:seed[5]` · AI: deterministic

Seed 5 ships exactly this state: test-5 WA-verified, `whatsapp_consent` at its DEFAULT (off), with due/overdue bills so a reminder exists to push.

**Steps:**
1. Sign in as test-5@azulzin.dev / test1234, open /notification_preferences → flip the 'receber no WhatsApp' toggle ON → save. Read the phone-note copy near the toggle.
2. Kick the sweep:
   ```
   bin/rails runner 'u=User.find_by!(email_address:"test-5@azulzin.dev"); Reminders::NotifyMemberJob.perform_now(u.account.id, u.id)'
   ```
   (Must be inside 08–21 America/Sao_Paulo for the WA push; the in-app Notification row is the reliable observable either way.)
3. Watch test-5's chat in the :3001 simulator.
4. Flip the toggle OFF, clear the rows (`bin/rails runner 'Notification.where(kind: "bill_due").delete_all'`), re-run the runner.

**Expect:** ON: the sweep now pushes to the WA chat — the first-ever push carries the 'responda parar' footer (NT-G-10); the phone-note copy near the toggle explains the verified-phone requirement. OFF: dashboard row only, no WA bubble (back to NT-G-03 behavior).

**Variants:**
- Phone-UNverified user flips the toggle — **pin the real behavior** (blocked with the phone note, or saved-but-undeliverable); the map leaves this open.

Pins: `app/views/notification_preferences/show.html.erb:84`, `app/controllers/notification_preferences_controller.rb:20`

### X-EXP-14 — Broken-key drill across WA + imports (extends WA-CAP-30 §2, WEB-IMP-07 §7)

Seed: `dev:seed_demo` · AI: broken-key

The catalog said "with network down" — this pins the exact reproducible trigger: a broken key makes every OpenRouter call 401 deterministically.

**Steps:**
1. Stop the stack and restart with a broken key: `OPENROUTER_API_KEY=broken bin/dev-fake` (use `GROQ_API_KEY=broken` instead to force WA-CAP-22's STT path).
2. Send `mercado 54,90` from marina's chat in the simulator.
3. Separately, upload sample.csv at /bank_accounts.
4. Tail `log/development.log` and watch the 3 `retry_on` attempts (~5s apart).

**Expect:** WA: after 3 attempts the fail_and_tell degrade fires — the message is marked failed FIRST, then the golden `whatsapp.replies.processing_failed` pt-BR reply lands in the simulator; no half-written transaction. Import: the status card leaves 'processing' and shows the visible failed state within ~60s.

**Variants:**
- Restore the real key, restart, and resend — the SAME message id is not reprocessed (already failed); a fresh message captures normally.

Pins: `app/jobs/process_inbound_whatsapp_job.rb:1`, `app/jobs/process_document_import_job.rb:1`
