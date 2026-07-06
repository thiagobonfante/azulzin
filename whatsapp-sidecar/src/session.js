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
        await this._markConnected('ready');
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
      this.logger.info(
        `Inbound message: from=${message.from} type=${message.type} ` +
        `ts=${message.timestamp} connectedAt=${this.connectedAt} hasMedia=${message.hasMedia}`
      );

      // Filter 1 — historical messages: without this a fresh QR scan replays
      // months of chat history as "transactions". Skippable (SKIP_HISTORY_FILTER) because
      // it compares the machine clock (connectedAt) to WhatsApp's message timestamp — a
      // skewed dev clock drops every live message. Keep it ON in production.
      if (!this.config.skipHistoryFilter &&
          this.connectedAt !== null && message.timestamp < this.connectedAt) {
        this.logger.info(
          `Dropping historical message (ts ${message.timestamp} < connectedAt ${this.connectedAt})`
        );
        return;
      }

      // Filter 2 — keep 1:1 DMs only. WhatsApp delivers those as @c.us OR @lid (its newer
      // linked-identity / privacy addressing); drop groups (@g.us), broadcasts and status.
      const from = message.from || '';
      if (!from.endsWith('@c.us') && !from.endsWith('@lid')) {
        this.logger.info(`Dropping non-DM message from ${from}`);
        return;
      }

      let media = null;
      let mediaTooLarge = false;
      if (message.hasMedia) {
        // WhatsApp reports the media byte size BEFORE download (message._data.size).
        // downloadMedia() materializes the whole file as a base64 string in this process's
        // heap-capped memory, so an oversized file (e.g. a 100MB PDF → ~133MB string) can
        // OOM the sidecar. Over the cap we skip the download and flag the message so Rails
        // asks the user to resend something smaller (the reply is localized in Rails — the
        // sidecar stays a dumb pipe). Unknown size (undefined) falls through and downloads.
        const mediaSize = message._data && message._data.size;
        if (mediaSize && mediaSize > this.config.mediaMaxBytes) {
          mediaTooLarge = true;
          this.logger.warn(
            `Skipping oversized media from ${message.from}: ${mediaSize} bytes > ` +
            `cap ${this.config.mediaMaxBytes} bytes`
          );
        } else {
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
      }

      const contact = await message.getContact();
      this.logger.info(
        `Contact resolved: number=${contact && contact.number} ` +
        `id=${contact && contact.id && contact.id._serialized}`
      );

      const data = {
        message_id: message.id.id,
        message_id_serialized: message.id._serialized, // globally-unique idempotency key
        from: message.from,
        to: message.to,
        body: message.body,
        timestamp: message.timestamp,
        has_media: message.hasMedia,
        media_too_large: mediaTooLarge,
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
  async sendMessage(target, message) {
    if (this.status !== 'connected' || !this.client) {
      const err = new Error('not_connected');
      err.code = 'NOT_CONNECTED';
      throw err;
    }

    // A full JID (contains '@', e.g. an @lid or @c.us) is used as-is; a bare number is
    // turned into a @c.us chat id. Replying to the exact inbound JID is what makes @lid
    // contacts (WhatsApp's linked-identity addressing) reachable.
    const chatId = String(target).includes('@')
      ? String(target)
      : `${String(target).replace(/\D/g, '')}@c.us`;

    await this._throttle();

    // The typing indicator is best-effort — getChatById can fail for some @lid contacts;
    // don't let that block the actual send.
    try {
      const chat = await this.client.getChatById(chatId);
      await chat.sendStateTyping();
      await this.sleep(1000 + Math.random() * 3000); // 1–4s randomized delay (anti-ban)
    } catch (err) {
      this.logger.warn(`getChatById(${chatId}) failed (${err.message}); sending without typing indicator`);
    }

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

  // Set connected state + notify Rails. Shared by the `ready` event and the state reconciler
  // below (whatsapp-web.js does not always fire `ready`, so we cannot rely on it alone).
  async _markConnected(reason) {
    const info = (this.client && this.client.info) || {};
    this.status = 'connected';
    this.phoneNumber = info.wid ? info.wid.user : this.phoneNumber || null;
    this.platform = info.platform || this.platform || null;
    this.pushname = info.pushname || this.pushname || null;
    this.connectedAt = Math.floor(Date.now() / 1000); // WhatsApp timestamps are unix seconds
    this.qrDataUrl = null;
    this.logger.info(`Marking connected (via ${reason}); phone=${this.phoneNumber}`);
    await this.webhook.notify('connected', {
      phone_number: this.phoneNumber,
      platform: this.platform,
      pushname: this.pushname,
    });
  }

  // --- Connection-state reconciler -----------------------------------------
  // Poll getState() periodically and reconcile our in-memory status with the real link:
  //   * getState() CONNECTED but status not 'connected'  → promote. whatsapp-web.js
  //     sometimes never fires `ready`, stranding us at 'authenticated'/'initializing' even
  //     though the socket is up; mirror the `ready` handler so the admin panel lights up and
  //     connectedAt is set (the historical-message filter needs it).
  //   * status 'connected' but getState() not CONNECTED  → demote to 'disconnected' (zombie
  //     session), so the admin panel reflects the dead link.

  startZombieGuard(intervalMs = 20000) {
    if (this.zombieTimer) return;
    this.zombieTimer = setInterval(() => {
      this._reconcileState().catch((err) => this.logger.error('State reconcile error:', err.message));
    }, intervalMs);
    if (this.zombieTimer.unref) this.zombieTimer.unref();
  }

  stopZombieGuard() {
    if (this.zombieTimer) {
      clearInterval(this.zombieTimer);
      this.zombieTimer = null;
    }
  }

  async _reconcileState() {
    if (!this.client) return;
    let state;
    try {
      state = await this.getState();
    } catch (err) {
      return; // transient (client still loading); try again next tick
    }
    if (state === 'CONNECTED' && this.status !== 'connected') {
      this.logger.warn(`State reconcile: getState()=CONNECTED but status '${this.status}' — marking connected (missed 'ready').`);
      await this._markConnected('state_check');
    } else if (state !== 'CONNECTED' && this.status === 'connected') {
      this.logger.warn(`Zombie session detected: status 'connected' but getState() = ${state}`);
      this.status = 'disconnected';
      await this.webhook.notify('disconnected', { reason: 'zombie_state_check' });
    }
  }
}

module.exports = SessionService;
