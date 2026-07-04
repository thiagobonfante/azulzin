# azulzin WhatsApp sidecar

A **single-session** Node/Express service that owns one WhatsApp Web session
(via [`whatsapp-web.js`](https://github.com/pedroslopez/whatsapp-web.js) +
LocalAuth on a persistent volume) and acts as a **dumb pipe** between WhatsApp
and the azulzin Rails app:

- inbound messages + media → `POST` to the Rails webhook,
- outbound text ← `POST /messages` from Rails,
- connection / QR events → pushed to Rails as they happen.

No AI, no business logic, no finance state — all of that lives in Rails. This is
a radically simplified, single-tenant fork of the multi-tenant `neowhats`
reference (no `account_id`/`branch_id`, no Postgres, one module-level client).

See the design plan: [`../.plans/whats/02-sidecar.md`](../.plans/whats/02-sidecar.md)
and the data-flow contract: [`../.plans/whats/01-architecture.md`](../.plans/whats/01-architecture.md).

## Run locally

```bash
cp .env.example .env      # then edit RAILS_WEBHOOK_URL + RAILS_API_TOKEN
npm install               # (dev: skip the Chromium download with PUPPETEER_SKIP_DOWNLOAD=true)
npm start                 # or: npm run dev  (nodemon)
```

The first boot has no saved session, so watch the logs / poll `GET /session/qr`
for a QR `data:` URL and scan it from WhatsApp → *Linked devices*. Once scanned,
the session is persisted under `SESSION_DATA_PATH/session-azulzin-main/` and
restored automatically on the next boot (no re-QR) as long as that path is a
persistent volume.

Run the tests (no real WhatsApp login required — the client is mocked):

```bash
npm test
```

## QR / connection flow

```
boot (or POST /session/initialize)
      │
      ▼
 client emits  qr          → status qr_pending  → webhook { event:"qr_code",  data:{ qr_data_url } }
 client emits  authenticated→ status authenticated→ webhook { event:"authenticated", data:{} }
 client emits  ready        → status connected    → webhook { event:"connected", data:{ phone_number, platform, pushname } }
                                                     connectedAt = now  (unix seconds)
 client emits  auth_failure → status auth_failed   → webhook { event:"auth_failed",  data:{ error } }
 client emits  disconnected → status disconnected  → webhook { event:"disconnected", data:{ reason } }
 client emits  message      → (filters) ─────────► webhook { event:"message_received", data:{…} }
```

A **zombie-session guard** polls `client.getState()` every ~2 min: if the
in-memory status says `connected` but the real state is not `CONNECTED`, it flips
to `disconnected` and pushes a `disconnected` webhook.

### Inbound filters (both mandatory)

1. **Historical messages** — if `message.timestamp < connectedAt` the message is
   dropped (a fresh QR scan otherwise replays months of history).
2. **Non-`@c.us` senders** — group (`@g.us`), `@broadcast` and `status@broadcast`
   messages are dropped (adding the number to a group must not fire the pipeline).

### `message_received` payload

```jsonc
{
  "event": "message_received",
  "timestamp": "2026-07-04T12:00:00.000Z",       // wall clock of the webhook POST
  "data": {
    "message_id": "3EB0ABCDEF",                   // message.id.id (hash)
    "message_id_serialized": "true_5511988887777@c.us_3EB0ABCDEF", // idempotency key — Rails dedupes on this
    "from": "5511988887777@c.us",
    "to": "5511999999999@c.us",
    "body": "gastei 50 no mercado",
    "timestamp": 1751630400,                       // unix seconds, WhatsApp server time
    "has_media": false,
    "type": "chat",                                // chat | ptt | audio | image | document | ...
    "contact_name": "Joao",
    "contact_number": "5511988887777",
    "media": null                                  // or { mimetype, data (base64), filename }
  }
}
```

Every event POSTs to `RAILS_WEBHOOK_URL` with `Authorization: Bearer
RAILS_API_TOKEN`, `Content-Type: application/json`, 5s timeout. On a network
failure the payload is retried from a slim in-memory queue with backoff
`[5s, 15s, 60s]`, max 3 retries (the base64 `media.data` is stripped from the
retained copy; media is dropped on retry — the user can re-send).

## HTTP API

All routes except `GET /health` require `Authorization: Bearer RAILS_API_TOKEN`.

| Method | Path                  | Body                          | Response |
|--------|-----------------------|-------------------------------|----------|
| GET    | `/health`             | —                             | `{ status:"ok", wa_status, wa_phone, connectedAt, state }` |
| POST   | `/session/initialize` | `{}`                          | `{ status }` |
| GET    | `/session/status`     | —                             | `{ status, phone_number, connectedAt }` |
| GET    | `/session/qr`         | —                             | `{ qr_data_url, status }` (meaningful only when `qr_pending`) |
| DELETE | `/session`            | —                             | `{ status:"logged_out" }` (logout + destroy) |
| POST   | `/messages`           | `{ phone_number, message }`   | `{ id, timestamp, ack }` · `409 { error:"not_connected" }` if the session is down |

`state` in `/health` is the real `client.getState()` so a monitor can tell a
live session (`CONNECTED`) apart from `qr_pending` or a zombie.

### `POST /messages` (outbound, text only)

```
POST /messages
Authorization: Bearer <RAILS_API_TOKEN>
Content-Type: application/json

{ "phone_number": "5511988887777", "message": "Confirmado ✅" }
```

`phone_number` is stripped to digits and suffixed with `@c.us`. The send applies
a global throttle (`SEND_MIN_INTERVAL_MS`), a typing indicator, and a randomized
1–4s delay (anti-ban). Returns `{ id, timestamp, ack }`, or `409
{ error: "not_connected" }` when the session is not connected.

## Environment

| Var | Default | Purpose |
|-----|---------|---------|
| `PORT` | `3001` | HTTP listen port |
| `NODE_ENV` | `development` | `production` in deploy |
| `RAILS_WEBHOOK_URL` | `http://localhost:3000/api/whatsapp/webhook` | single webhook endpoint (no tenant path) |
| `RAILS_API_TOKEN` | `development-token` | shared bearer secret, **both** directions |
| `SESSION_DATA_PATH` | `./.wwebjs_auth` | LocalAuth dir — **must be a persistent volume** |
| `PUPPETEER_EXECUTABLE_PATH` | (bundled) | system Chromium path (`/usr/bin/chromium` in Docker) |
| `SEND_MIN_INTERVAL_MS` | `1500` | min interval between outbound sends |
| `SKIP_AUTO_RECONNECT` | `false` | if `true`, don't auto-initialize on boot |

## Docker

```bash
docker build -t azulzin-whatsapp-sidecar .
docker run -p 3001:3001 --env-file .env \
  -v azulzin_wa_session:/app/.wwebjs_auth \
  azulzin-whatsapp-sidecar
```

The image installs system Chromium and runs non-root with a 1 GB heap cap and a
`/health` healthcheck. The session volume is the one piece of durable state — it
must survive redeploys or every deploy forces a fresh QR scan.

## How it fits azulzin

The sidecar is **server-to-server** with Rails and should not be publicly
routable (private network / localhost). The only public surface is the Rails
webhook path, protected by the shared bearer token. Rails resolves the sender to
a verified user, dedupes on `message_id_serialized`, and runs the transcription /
extraction / reply pipeline. Full flow and Rails integration:
[`../.plans/whats/01-architecture.md`](../.plans/whats/01-architecture.md) ·
[`../.plans/whats/03-rails-integration.md`](../.plans/whats/03-rails-integration.md).
