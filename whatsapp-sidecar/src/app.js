const express = require('express');
const cors = require('cors');
const createAuth = require('./middleware/auth');
const { errorHandler, notFoundHandler } = require('./middleware/error');

/**
 * Build the Express app around an injected session service.
 * @param {Object} deps
 * @param {Object} deps.config
 * @param {Object} deps.session - SessionService instance
 * @returns {express.Application}
 */
function createApp({ config, session }) {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: '1mb' })); // inbound bodies are small (text sends / control)

  // Health check — NO auth. Reports the real getState() so a monitor can tell a
  // live session apart from a zombie (status 'connected' but state != CONNECTED).
  app.get('/health', async (req, res) => {
    const state = await session.getState();
    res.json({
      status: 'ok',
      wa_status: session.status,
      wa_phone: session.phoneNumber,
      connectedAt: session.connectedAt,
      state,
    });
  });

  // Everything below requires the shared bearer token.
  app.use(createAuth(config));

  app.post('/session/initialize', async (req, res, next) => {
    try {
      await session.initialize();
      res.json({ status: session.status });
    } catch (err) {
      next(err);
    }
  });

  app.get('/session/status', (req, res) => {
    res.json(session.getStatus());
  });

  app.get('/session/qr', (req, res) => {
    res.json(session.getQR());
  });

  app.delete('/session', async (req, res, next) => {
    try {
      await session.logout();
      res.json({ status: session.status });
    } catch (err) {
      next(err);
    }
  });

  app.post('/messages', async (req, res, next) => {
    const { phone_number, message } = req.body || {};
    if (!phone_number || !message) {
      return res.status(400).json({ error: 'phone_number and message are required' });
    }
    try {
      const result = await session.sendMessage(phone_number, message);
      res.json(result);
    } catch (err) {
      if (err.code === 'NOT_CONNECTED') {
        return res.status(409).json({ error: 'not_connected' });
      }
      next(err);
    }
  });

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = createApp;
