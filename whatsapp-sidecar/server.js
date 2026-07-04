const config = require('./src/config');
const logger = require('./src/logger');
const WebhookService = require('./src/webhook');
const SessionService = require('./src/session');
const createApp = require('./src/app');

/**
 * Server entry point. Wires the webhook queue + single session into the app and
 * handles boot / graceful shutdown.
 */
const webhook = new WebhookService({ config, logger });
const session = new SessionService({ config, logger, webhook });
const app = createApp({ config, session });

const server = app.listen(config.port, () => {
  logger.info(`WhatsApp sidecar running on port ${config.port}`);
  logger.info(`Rails webhook URL: ${config.railsWebhookUrl}`);

  webhook.start();
  session.startZombieGuard();

  if (config.skipAutoReconnect) {
    logger.warn('Auto-reconnect SKIPPED (SKIP_AUTO_RECONNECT=true) — waiting for POST /session/initialize');
  } else {
    // LocalAuth restores an existing session from the volume → `ready` with no QR.
    setTimeout(() => {
      session.initialize().catch((err) => logger.error('Initial client init failed:', err));
    }, 2000);
  }
});

// Graceful shutdown: stop retry queue → destroy client (kills Chrome) →
// close server → hard exit after 10s.
let shuttingDown = false;
const shutdown = async () => {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info('Shutdown signal received, shutting down gracefully...');

  webhook.stop();
  await session.destroy();

  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });

  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000).unref();
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
