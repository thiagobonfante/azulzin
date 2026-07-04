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
  puppeteerExecutablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined,

  // Global outbound send throttle (ms).
  sendMinIntervalMs: parseInt(process.env.SEND_MIN_INTERVAL_MS || '1500', 10),

  // Skip auto-initialize on boot (wait for POST /session/initialize instead).
  skipAutoReconnect: process.env.SKIP_AUTO_RECONNECT === 'true',
};
