# WhatsApp channel — how it works & go-live

azulzin captures expenses from WhatsApp: a user sends a **voice note**, a **receipt photo**,
or **typed text** to one commercial number; azulzin transcribes/OCRs it, extracts the
amount + merchant + date + payment method, matches it to the user's own account/card, and —
under the decided **silent auto-commit** posture — records it, letting the user reverse or
reassign it in the app. It is an ingestion funnel, not a chatbot.

Outbound posture: **reply-only, plus opted-in proactive notifications**
([ADR 0011](decisions/0011-proactive-notifications.md)) — bill reminders and budget alerts
push to members who flipped the `whatsapp_consent` switch (default off), fail-closed behind
a per-user daily cap, quiet hours and an atomic send claim; every send is a logged
`WhatsappMessage`, and replying "parar" turns the push off instantly.

Design of record: [`.plans/whats/`](../.plans/whats/) (gitignored). This doc is the
operational summary + the steps to take it live.

## Architecture

```
WhatsApp ⇄ Node sidecar (whatsapp-web.js, headless Chromium, LocalAuth)
             │  POST /api/whatsapp/webhook  (shared bearer token)
             ▼
        Rails webhook  ──►  ProcessInboundWhatsappJob (solid_queue, per-user serialized)
                                │  audio → Groq STT ; image → OpenRouter vision ; text → body
                                │  → Extractor → Matcher → Confidence → Decider
                                ▼
                        Transaction (pure record)  +  pt-BR reply back through the sidecar
```

- **Sidecar** (`whatsapp-sidecar/`): a dumb pipe — owns the WhatsApp session, forwards
  inbound messages+media to Rails, exposes `POST /messages` to send. No AI, no business logic.
- **Rails**: `Api::Whatsapp::WebhooksController` (bearer auth, always 200-fast) →
  `ProcessInboundWhatsappJob` (serialized per user). Services under `app/services/whatsapp/`.
- **Identity**: only a **verified, unique** `whatsapp_id` is ever attributed money; ambiguous
  matches are refused. Users verify by texting an `AZUL-XXXX` code to the number.
- **Decision** (`Whatsapp::Decider`): amount present & confidence ≥ **floor** (default 80) →
  `posted` (assigned if the instrument is a confident match, else **unassigned** for in-app
  pick); confidence < floor → `pending_review` (park); no amount → the one WhatsApp question
  "quanto foi?". The app is the safety net (reverse / reassign / edit).

## What's implemented (all tests green)

Phases 0–6 of the plan: schema + models, the sidecar, the webhook + verification, the
per-user job, text/audio/image extraction, matching + confidence + decisioning, the admin
panel (QR connection management) + in-app inbox, and hardening (retention purge, rate limit,
LGPD cascade). The two external boundaries — the **WhatsApp transport** and the **AI
providers** — are behind adapters that are stubbed in tests. Going live means supplying real
credentials and scanning the QR.

## Go-live checklist (needs you)

### 1. Credentials & env

Rails reads secrets from encrypted credentials first, then ENV. Add via
`bin/rails credentials:edit`:

```yml
openrouter:
  api_key: sk-or-...        # or ENV OPENROUTER_API_KEY
groq:
  api_key: gsk_...          # or ENV GROQ_API_KEY    (speech-to-text)
whatsapp:
  service_token: <long random shared secret>   # prod only; dev uses the Procfile default
```

Rails ENV (optional overrides): `WHATSAPP_SERVICE_URL` (default `http://localhost:3001`),
`WHATSAPP_CONFIDENCE_FLOOR` (default 80), `WHATSAPP_RETENTION_DAYS` (default 60),
`APP_URL` (OpenRouter referer).

Sidecar `.env` (see `whatsapp-sidecar/.env.example`): `RAILS_WEBHOOK_URL`
(`https://app.azulzin.com.br/api/whatsapp/webhook`), `RAILS_API_TOKEN` (**must equal**
`whatsapp.service_token`), `SESSION_DATA_PATH`, `PUPPETEER_EXECUTABLE_PATH`.

### 2. ⚠️ Verify the AI model slugs (before trusting audio/receipts)

Every model id is a **placeholder** — verify against the live provider lists and pin exact
slugs (Review P1-1):
- STT: `GROQ_STT_MODEL` (default `whisper-large-v3-turbo`) against Groq's model list.
- Extraction/vision: `config/openrouter.yml` (`extraction`, `vision`) against OpenRouter's
  model list. Confirm the vision model supports strict `json_schema`.
- Also confirm **zero-data-retention / logging-off** in both provider accounts (financial PII).

### 3. Run the sidecar & scan the QR

**Dev:** `bin/dev` now starts the sidecar (`:3001`) alongside Rails (`:3000`) and the Tailwind
watcher — one command, defined in `Procfile.dev`. First time only: `cd whatsapp-sidecar && npm ci`.
The sidecar shares a dev bearer token with Rails via the Procfile (`WHATSAPP_SERVICE_TOKEN`,
default `dev-whatsapp-token`); its machine-specific Chromium path lives in the gitignored
`whatsapp-sidecar/.env` (set to your installed Google Chrome). It boots with
`SKIP_AUTO_RECONNECT=true`, so no browser launches until you click Connect.

**Prod:** run the sidecar from its Dockerfile on an always-on host (persistent volume at
`/app/.wwebjs_auth`), with `RAILS_API_TOKEN` = `whatsapp.service_token`.

Then in the app, as an **admin**, open `/admin/whatsapp_connection` and click Connect — the
QR appears live; scan it with the commercial number's WhatsApp (linked-device). Seed the first
admin in the console: `User.find_by(email_address: "you@…").update!(admin: true)`.

**Number hygiene** (wwebjs ban-risk mitigation): warm the number with real human use before
scanning; stay reply-only plus the opted-in proactive notifications above (ADR 0011); keep a
backup number. The sidecar already throttles outbound and
runs a zombie-session guard. Migration triggers to the official Cloud API: see
[`.plans/whats/08-security-and-ops.md`](../.plans/whats/08-security-and-ops.md).

### 4. Onboarding hookup (small remaining UI task)

The verification handshake works end-to-end at the model/webhook layer
(`User#whatsapp_verification_code!` → the user texts the code → `verify_whatsapp!`). Surfacing
the code + "envie para +55…" instructions in the onboarding/profile UI is the one piece left
to wire into the wizard.

## Operations

- **Hosting**: one always-on machine for the sidecar (no auto-stop — it would drop the
  session), persistent volume at `/app/.wwebjs_auth`, ~1–1.5 GB RAM.
- **Health**: `WhatsappServiceHealthCheckJob` (recurring) → admin badge; the sidecar's
  `/health` reports the real `client.getState()`.
- **Retention**: `WhatsappRetentionJob` purges media + transcripts older than
  `WHATSAPP_RETENTION_DAYS` (schedule it in `config/recurring.yml`).
- **Tuning the floor**: launch with the floor high (parks more), then lower it as the in-app
  correction rate proves the extraction trustworthy.

## Tests

`bin/rails test` (Rails), `cd whatsapp-sidecar && npm test` (sidecar). The AI/transport
boundaries are stubbed, so the suite runs with no keys and no WhatsApp connection.
