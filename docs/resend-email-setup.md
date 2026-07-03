# Resend email setup (production)

How to make transactional email (verification + password reset) actually deliver in
production. The app code is done: `config/environments/production.rb` sends via Resend
SMTP (`smtp.resend.com:465`, user `resend`, password from `credentials.resend.api_key`),
`From: no-reply@azulzin.com.br`, mailers localized per recipient, delivered via
`deliver_later` on Solid Queue. What's left is **the API key** (done — already in
credentials) and **verifying the sending domain's DNS** so mail isn't rejected/spam-filed.

Decision + rationale: [ADR 0003](decisions/0003-transactional-email-provider.md).

## 1. API key (already done)

`resend.api_key` is in encrypted credentials (`re_…`). To confirm:

```bash
bin/rails runner 'puts Rails.application.credentials.dig(:resend,:api_key).present?'  # => true
```

Dev doesn't use Resend (mail opens in the browser via `letter_opener`); the key is only
exercised in production.

## 2. Verify the sending domain (Resend dashboard → DNS)

In <https://resend.com> → **Domains → Add Domain**, enter `azulzin.com.br` (or a subdomain
like `send.azulzin.com.br` — a subdomain keeps the root domain's email reputation separate;
either works as long as the `From` matches). Pick the **region** (US or EU) — this only
affects the MX feedback host, not the SMTP host.

Resend then shows a set of **DNS records to add at your DNS provider** (registrar / Cloudflare
/ Route53). Copy them exactly — the DKIM value is generated per-domain. Typically:

| Type | Host | Value (copy from Resend) | Purpose |
|---|---|---|---|
| **MX** | `send` (or the domain) | `feedback-smtp.<region>.amazonses.com` (priority 10) | bounce/complaint feedback |
| **TXT (SPF)** | `send` | `v=spf1 include:amazonses.com ~all` | authorizes the sender |
| **TXT (DKIM)** | `resend._domainkey` | `p=<long public key from Resend>` | signs messages |
| **TXT (DMARC)** *(recommended)* | `_dmarc` | `v=DMARC1; p=none;` | reporting policy (start at `none`) |

Add them, then click **Verify** in Resend. Propagation is usually minutes but can take up to
a few hours. The domain must read **Verified** before production mail sends reliably.

## 3. Confirm the From matches

The `From` address (`no-reply@azulzin.com.br`, set in `app/mailers/application_mailer.rb`)
**must be on the verified domain**, or Resend rejects the message. If you verified a
subdomain instead (e.g. `send.azulzin.com.br`), change the `From` to
`no-reply@send.azulzin.com.br` to match.

## 4. Verify end-to-end after deploy

- Ensure `RAILS_MASTER_KEY` is on the server (Kamal `env.secret`) so the key decrypts.
- Ensure Solid Queue is processing jobs — we run it in Puma via `SOLID_QUEUE_IN_PUMA: true`
  (already set in `config/deploy.yml`), so `deliver_later` actually sends.
- Trigger a real password reset → the email should arrive (not spam), with the link pointing
  at `https://azulzin.com.br`. Because `raise_delivery_errors = true`, SMTP failures show up
  as **failed Solid Queue jobs** — watch the failed-jobs table if nothing arrives.

## Switching providers later

Moving off Resend is a `config.action_mailer.smtp_settings` (`address`/`port`/`user_name`) +
credentials-key change with **no app code** — see ADR 0003. Mailgun was declined (no permanent
free tier).
