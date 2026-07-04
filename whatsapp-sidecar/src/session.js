const qrcode = require('qrcode');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Default factory for the real whatsapp-web.js client. Required lazily so unit
 * tests (which inject a mock clientFactory) never load puppeteer.
 */
function defaultClientFactory(config) {
  const { Client, LocalAuth } = require('whatsapp-web.js');
  return () =>
    new Client({
      authStrategy: new LocalAuth({ clientId: config.clientId, dataPath: config.sessionDataPath }),
      puppeteer: {
        headless: true,
        executablePath: config.puppeteerExecutablePath,
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-accelerated-2d-canvas',
          '--no-first-run',
          '--no-zygote',
          '--disable-gpu',
        ],
      },
    });
}

/**
 * Single-session WhatsApp client manager. Owns one wwebjs client, mirrors its
 * status in memory, forwards inbound messages to Rails via the webhook service,
 * and exposes send / lifecycle operations. No multi-tenancy, no database.
 *
 * Status vocabulary:
 *   initializing | qr_pending | authenticated | connected |
 *   disconnected | auth_failed | logged_out
 *
 * Dependencies are injected so the client and clock are mockable in tests.
 */
class SessionService {
  constructor({ config, logger, webhook, clientFactory, sleep: sleepFn } = {}) {
    this.config = config;
    this.logger = logger;
    this.webhook = webhook;
    this.clientFactory = clientFactory || defaultClientFactory(config);
    this.sleep = sleepFn || sleep;

    this.client = null;
    this.status = 'initializing';
    this.phoneNumber = null;
    this.platform = null;
    this.pushname = null;
    this.connectedAt = null; // unix seconds, set on `ready`
    this.qrDataUrl = null;

    this.lastSendAt = 0; // for the global send throttle
    this.zombieTimer = null;
  }

  /** Boot the client. LocalAuth restores an existing session (no QR) if present. */
  async initialize() {
    if (this.client) {
      this.logger.info('Client already initialized');
      return;
    }
    this.logger.info('Initializing WhatsApp client');
    this.status = 'initializing';
    this.client = this.clientFactory();
    this._setupEvents();

    try {
      await this.client.initialize();
    } catch (err) {
      this.logger.error('Error initializing client:', err);
      this.client = null;
      throw err;
    }
  }

  _setupEvents() {
    const client = this.client;

    client.on('qr', async (qr) => {
      this.logger.info('QR code generated');
      try {
        this.qrDataUrl = await qrcode.toDataURL(qr);
        this.status = 'qr_pending';
        await this.webhook.notify('qr_code', { qr_data_url: this.qrDataUrl });
      } catch (err) {
        this.logger.error('Error generating QR code:', err);
      }
    });

    client.on('authenticated', async () => {
      this.logger.info('Client authenticated');
      this.status = 'authenticated';
      await this.webhook.notify('authenticated', {});
    });

    client.on('ready', async () => {
      this.logger.info('Client ready');
      try {
        const info = this.client.info || {};
        this.status = 'connected';
        this.phoneNumber = info.wid ? info.wid.user : null;
        this.platform = info.platform || null;
        this.pushname = info.pushname || null;
        this.connectedAt = Math.floor(Date.now() / 1000); // WhatsApp timestamps are unix seconds
        this.qrDataUrl = null;
        await this.webhook.notify('connected', {
          phone_number: this.phoneNumber,
          platform: this.platform,
          pushname: this.pushname,
        });
      } catch (err) {
        this.logger.error('Error handling ready event:', err);
      }
    });

    client.on('auth_failure', async (msg) => {
      this.logger.error('Authentication failed:', msg);
      this.status = 'auth_failed';
      await this.webhook.notify('auth_failed', { error: msg });
    });

    client.on('disconnected', async (reason) => {
      this.logger.info('Client disconnected:', reason);
      this.status = 'disconnected';
      await this.webhook.notify('disconnected', { reason });
    });

    client.on('message', (message) => this._handleMessage(message));
  }

  /**
   * Normalize and forward an inbound message. Wrapped in try/catch so a single
   * bad message can never crash the client.
   */
  async _handleMessage(message) {
    try {
      // Filter 1 — historical messages: without this a fresh QR scan replays
      // months of chat history as "transactions".
      if (this.connectedAt !== null && message.timestamp < this.connectedAt) {
        this.logger.info(
          `Dropping historical message (ts ${message.timestamp} < connectedAt ${this.connectedAt})`
        );
        return;
      }

      // Filter 2 — non-@c.us: drop groups (@g.us), broadcasts and status updates.
      const from = message.from || '';
      if (!from.endsWith('@c.us')) {
        this.logger.info(`Dropping non-@c.us message from ${from}`);
        return;
      }

      let media = null;
      if (message.hasMedia) {
        try {
          const downloaded = await message.downloadMedia(); // may return undefined
          if (downloaded) {
            media = {
              mimetype: downloaded.mimetype,
              data: downloaded.data, // base64
              filename: downloaded.filename,
            };
          }
        } catch (err) {
          this.logger.error('Error downloading media:', err);
          // Forward the message without media — Rails can ask the user to resend.
        }
      }

      const contact = await message.getContact();

      const data = {
        message_id: message.id.id,
        message_id_serialized: message.id._serialized, // globally-unique idempotency key
        from: message.from,
        to: message.to,
        body: message.body,
        timestamp: message.timestamp,
        has_media: message.hasMedia,
        type: message.type,
        contact_name: contact.pushname || contact.name,
        contact_number: contact.number,
        media,
      };

      await this.webhook.notify('message_received', data);
    } catch (err) {
      this.logger.error('Error handling incoming message:', err);
    }
  }

  /**
   * Send a text message. Throws a NOT_CONNECTED error if the session is down.
   * Applies the global throttle + a human-like typing indicator and 1–4s delay.
   */
  async sendMessage(phoneNumber, message) {
    if (this.status !== 'connected' || !this.client) {
      const err = new Error('not_connected');
      err.code = 'NOT_CONNECTED';
      throw err;
    }

    const chatId = `${String(phoneNumber).replace(/\D/g, '')}@c.us`;

    await this._throttle();

    const chat = await this.client.getChatById(chatId);
    await chat.sendStateTyping();
    await this.sleep(1000 + Math.random() * 3000); // 1–4s randomized delay (anti-ban)

    const sent = await this.client.sendMessage(chatId, message);
    this.logger.info(`Message sent to ${chatId}`);
    return { id: sent.id.id, timestamp: sent.timestamp, ack: sent.ack };
  }

  /** Enforce a minimum interval between two sends (global anti-ban throttle). */
  async _throttle() {
    const wait = this.lastSendAt + this.config.sendMinIntervalMs - Date.now();
    if (wait > 0) await this.sleep(wait);
    this.lastSendAt = Date.now();
  }

  /** Real WhatsApp connection state ('CONNECTED', etc.), or null if no client. */
  async getState() {
    if (!this.client) return null;
    try {
      return await this.client.getState();
    } catch (err) {
      return null;
    }
  }

  getStatus() {
    return { status: this.status, phone_number: this.phoneNumber, connectedAt: this.connectedAt };
  }

  getQR() {
    return { qr_data_url: this.qrDataUrl, status: this.status };
  }

  /**
   * Permanent logout: delete the session from disk, kill Chrome, emit logged_out.
   * A reconnect afterwards requires a fresh QR scan.
   */
  async logout() {
    if (this.client) {
      try {
        if (this.client.authStrategy && this.client.authStrategy.logout) {
          await this.client.authStrategy.logout();
        }
      } catch (err) {
        this.logger.error('Error during authStrategy.logout:', err);
      }
      try {
        await this.client.destroy();
      } catch (err) {
        this.logger.error('Error destroying client:', err);
      }
    }
    this.client = null;
    this.status = 'logged_out';
    this.phoneNumber = null;
    this.connectedAt = null;
    this.qrDataUrl = null;
    await this.webhook.notify('logged_out', {});
  }

  /** Kill the browser without deleting the session (used on graceful shutdown). */
  async destroy() {
    this.stopZombieGuard();
    if (this.client) {
      try {
        await this.client.destroy();
      } catch (err) {
        this.logger.error('Error destroying client:', err);
      }
      this.client = null;
    }
  }

  // --- Zombie-session guard ------------------------------------------------
  // Poll getState() periodically. If in-memory status says 'connected' but the
  // real link is down, flip to 'disconnected' and notify so the admin panel lights up.

  startZombieGuard(intervalMs = 120000) {
    if (this.zombieTimer) return;
    this.zombieTimer = setInterval(() => {
      this._checkZombie().catch((err) => this.logger.error('Zombie check error:', err.message));
    }, intervalMs);
    if (this.zombieTimer.unref) this.zombieTimer.unref();
  }

  stopZombieGuard() {
    if (this.zombieTimer) {
      clearInterval(this.zombieTimer);
      this.zombieTimer = null;
    }
  }

  async _checkZombie() {
    if (this.status !== 'connected' || !this.client) return;
    const state = await this.getState();
    if (state !== 'CONNECTED') {
      this.logger.warn(`Zombie session detected: status 'connected' but getState() = ${state}`);
      this.status = 'disconnected';
      await this.webhook.notify('disconnected', { reason: 'zombie_state_check' });
    }
  }
}

module.exports = SessionService;
