const axios = require('axios');

/**
 * Webhook delivery to Rails, with a slim in-memory retry queue.
 *
 * - Every event POSTs to the single RAILS_WEBHOOK_URL with a Bearer token.
 * - On a delivery failure the payload is enqueued (media.data stripped to avoid
 *   memory bloat) and retried with backoff [5s, 15s, 60s], max 3 retries.
 * - The queue is single, global, and ordered. It is in-memory only: buffered
 *   items are lost on a crash (acceptable for MVP — the user simply re-sends).
 *
 * `httpClient` is injectable for testing (defaults to axios).
 */
class WebhookService {
  constructor({ config, logger, httpClient } = {}) {
    this.config = config;
    this.logger = logger;
    this.http = httpClient || axios;

    this.queue = [];
    this.backoff = [5000, 15000, 60000]; // 5s, 15s, 60s
    this.maxRetries = 3;
    this.intervalMs = 5000;
    this.timer = null;
  }

  /**
   * Deliver an event. Attempts once inline; on failure enqueues for retry.
   * @returns {Promise<boolean>} true if delivered on the first attempt.
   */
  async notify(event, data) {
    const ok = await this._send({ event, data });
    if (!ok) this._enqueue(event, data);
    return ok;
  }

  /** POST a single payload. Never throws. */
  async _send({ event, data }) {
    try {
      await this.http.post(
        this.config.railsWebhookUrl,
        { event, data, timestamp: new Date().toISOString() },
        {
          headers: {
            Authorization: `Bearer ${this.config.railsApiToken}`,
            'Content-Type': 'application/json',
          },
          timeout: 5000,
        }
      );
      return true;
    } catch (err) {
      const detail = err.response ? `HTTP ${err.response.status}` : err.message;
      this.logger.error(`Webhook delivery failed (${event}): ${detail}`);
      return false;
    }
  }

  /**
   * Enqueue a failed delivery for retry. The base64 media payload is stripped
   * from the retained copy so the retry buffer never holds multi-MB blobs.
   */
  _enqueue(event, data) {
    let retained = data;
    if (data && data.media && data.media.data) {
      retained = { ...data, media: { ...data.media, data: undefined, stripped: true } };
    }
    this.queue.push({
      event,
      data: retained,
      attempts: 0,
      nextAttemptAt: Date.now() + this.backoff[0],
    });
    this.logger.warn(`Webhook (${event}) enqueued for retry (queue size: ${this.queue.length})`);
  }

  /**
   * Process every item whose backoff window has elapsed. Deterministic:
   * accepts `now` so tests can drive time without fake timers.
   */
  async processQueue(now = Date.now()) {
    const due = this.queue.filter((item) => item.nextAttemptAt <= now);
    for (const item of due) {
      const ok = await this._send({ event: item.event, data: item.data });
      if (ok) {
        this._remove(item);
        this.logger.info(`Webhook (${item.event}) delivered on retry`);
        continue;
      }
      item.attempts += 1;
      if (item.attempts >= this.maxRetries) {
        this._remove(item);
        this.logger.error(`Webhook (${item.event}) dropped after ${this.maxRetries} retries`);
      } else {
        const delay = this.backoff[Math.min(item.attempts, this.backoff.length - 1)];
        item.nextAttemptAt = now + delay;
      }
    }
  }

  _remove(item) {
    const idx = this.queue.indexOf(item);
    if (idx !== -1) this.queue.splice(idx, 1);
  }

  start() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      this.processQueue().catch((err) => this.logger.error('Retry queue error:', err.message));
    }, this.intervalMs);
    if (this.timer.unref) this.timer.unref();
    this.logger.info(`Webhook retry queue started (interval ${this.intervalMs}ms, max ${this.maxRetries} retries)`);
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
      this.logger.info('Webhook retry queue stopped');
    }
  }
}

module.exports = WebhookService;
