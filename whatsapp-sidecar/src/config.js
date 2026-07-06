require('dotenv').config();

/**
 * Centralized configuration for the single-session sidecar.
 * All values come from the environment (see .env.example).
 */
module.exports = {
  port: parseInt(process.env.PORT || '3001', 10),
  nodeEnv: process.env.NODE_ENV || 'development',

  // Single Rails webhook URL — no per-tenant path (azulzin is single-session).
  railsWebhookUrl: process.env.RAILS_WEBHOOK_URL || 'http://localhost:3000/api/whatsapp/webhook',
  // Shared bearer secret, both directions.
  railsApiToken: process.env.RAILS_API_TOKEN || 'development-token',

  // LocalAuth session storage.
  clientId: 'azulzin-main',
  sessionDataPath: process.env.SESSION_DATA_PATH || './.wwebjs_auth',

  // Pinned WhatsApp Web version (fetched from wppconnect/wa-version). whatsapp-web.js 1.34.7's
  // bundled default (2.3000.1017…) is deprecated by WhatsApp, which strands the client at
  // `authenticated` with no `ready` event and no inbound messages. Bump this when reception
  // breaks again (pick a current build from github.com/wppconnect-team/wa-version/tree/main/html).
  webVersion: process.env.WHATSAPP_WEB_VERSION || '2.3000.1042650569-alpha',
  puppeteerExecutablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,

  // Global outbound send throttle (ms).
  sendMinIntervalMs: parseInt(process.env.SEND_MIN_INTERVAL_MS || '1500', 10),

  // Max media byte size to download. WhatsApp reports the size before download, so over
  // this cap we skip downloadMedia() entirely — it would otherwise materialize the whole
  // file as a base64 string in this process's (heap-capped) memory and can OOM it. Rails
  // then asks the user to resend a smaller file. Default 16 MiB (WhatsApp's own media cap).
  mediaMaxBytes: parseInt(process.env.MEDIA_MAX_BYTES || String(16 * 1024 * 1024), 10),

  // Skip auto-initialize on boot (wait for POST /session/initialize instead).
  skipAutoReconnect: process.env.SKIP_AUTO_RECONNECT === 'true',

  // Skip the historical-message filter. That filter compares WhatsApp's message timestamp
  // to the machine clock (connectedAt); a skewed dev clock (e.g. set to the future) makes
  // every live message look "historical" and get dropped. Turn ON in dev, keep OFF in prod.
  skipHistoryFilter: process.env.SKIP_HISTORY_FILTER === 'true',
};
