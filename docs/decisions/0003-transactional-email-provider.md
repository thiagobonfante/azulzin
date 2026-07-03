# 3. Transactional email provider: one provider (Resend recommended)

## Status

Accepted (2026-07-03) — **Resend** chosen; Mailgun declined.

## Context

Email confirmation and password reset need reliable transactional email. The user proposed Mailgun's free tier. We send via Action Mailer `deliver_later` on Solid Queue over SMTP, secrets in Rails encrypted credentials. Volume is low (verification + reset only).

Provider landscape (verify current terms at setup time — these move):
- **Resend** — free tier ~3,000/mo (100/day), 1 custom domain, real SMTP (`smtp.resend.com:465`, TLS, user `resend`, password = API key). 6-line Rails config. Cleanest DX.
- **Mailgun** — no longer offers a permanent free tier (a time-limited trial, then pay-as-you-go). Real SMTP, but historically two footguns: new accounts start on a sandbox domain that only sends to ≤5 authorized recipients until a custom domain is DNS-verified, and EU vs US regions use different SMTP/API hosts chosen at domain creation (not swappable).
- **Postmark** — best-in-class deliverability but a very small free tier (~100/month).
- **Amazon SES** — cheapest at scale, heavy setup (sandbox → prod-access request, IAM, manual DKIM).
- **SendGrid** — free plan retired; not an option.

The earlier draft carried full SMTP config for two providers and cited a "30× headroom" figure that did not follow from its own numbers. Both are corrected here: we ship exactly one config, and we do not make quantitative headroom claims.

## Decision

Ship a **single provider config**. Recommend **Resend**: trivial Rails wiring and a genuine standing free tier, avoiding Mailgun's sandbox and region footguns and its now-removed permanent free tier. Wire as `config.action_mailer.delivery_method = :smtp` with `deliver_later`; API key in credentials (`resend.api_key`). Prefer SMTP over any provider HTTP gem — Action Mailer + Solid Queue already gives retries/backoff, so an extra gem buys nothing at this volume. Development uses `letter_opener`; test uses `:test`.

The user proposed Mailgun but confirmed Resend after reviewing that Mailgun no longer has a permanent free tier. Should we ever switch, it is a credentials + `smtp_settings` (address/port/user) swap with **no app code change** — so we do not maintain a second config in-tree.

## Consequences

- One SMTP block to read and secure; the resend-verification button is rate-limited to respect daily caps.
- With `deliver_later`, SMTP failures surface as failed Solid Queue jobs, not request errors — monitor the failed-jobs table. `raise_delivery_errors = true` in production makes those jobs fail loudly.
- A verified sending domain with SPF + DKIM + DMARC is required regardless of provider, or mail lands in spam.
- The production mailer host (currently the `example.com` placeholder) and the `ApplicationMailer` From (currently `from@example.com`) must both be set before shipping, or confirmation/reset mail breaks or bounces.
- Choosing Mailgun instead is a config + credentials change only.

## Alternatives considered

- **Mailgun as primary (user's proposal)** — real SMTP, but no permanent free tier now, plus the sandbox-recipient and EU/US-region footguns. Kept as the drop-in alternative, documented via the open question rather than a second in-tree config.
- **Carrying both provider configs** — more surface than the one provider requested, against CLAUDE.md simplicity. Rejected.
- **Postmark** — best deliverability, free tier too small for production; a good escalation if mail lands in spam.
- **Amazon SES / SendGrid** — over-engineered / no longer free. Rejected.
