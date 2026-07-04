const WebhookService = require('../src/webhook');
const { silentLogger, testConfig } = require('./helpers');

function makeWebhook(httpClient) {
  return new WebhookService({ config: testConfig, logger: silentLogger, httpClient });
}

const mediaPayload = () => ({
  message_id_serialized: 'true_x@c.us_ABC',
  body: 'receipt',
  media: { mimetype: 'image/jpeg', data: 'QkFTRTY0AAAA', filename: 'r.jpg' },
});

describe('WebhookService delivery + retry queue', () => {
  test('delivers on the first attempt and does not enqueue', async () => {
    const http = { post: jest.fn().mockResolvedValue({ status: 200 }) };
    const webhook = makeWebhook(http);

    const ok = await webhook.notify('message_received', { a: 1 });

    expect(ok).toBe(true);
    expect(http.post).toHaveBeenCalledTimes(1);
    expect(webhook.queue).toHaveLength(0);
    // Verify auth header + payload envelope.
    const [url, body, opts] = http.post.mock.calls[0];
    expect(url).toBe(testConfig.railsWebhookUrl);
    expect(body).toMatchObject({ event: 'message_received', data: { a: 1 } });
    expect(opts.headers.Authorization).toBe('Bearer test-token');
  });

  test('(f) on failure, enqueues a copy with media.data stripped', async () => {
    const http = { post: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')) };
    const webhook = makeWebhook(http);

    const ok = await webhook.notify('message_received', mediaPayload());

    expect(ok).toBe(false);
    expect(webhook.queue).toHaveLength(1);
    const item = webhook.queue[0];
    expect(item.data.media.data).toBeUndefined(); // base64 stripped
    expect(item.data.media.stripped).toBe(true);
    expect(item.data.media.mimetype).toBe('image/jpeg'); // metadata retained
    expect(item.data.body).toBe('receipt');
  });

  test('(f) retries with backoff [5s, 15s, 60s] then drops after 3 retries', async () => {
    const http = { post: jest.fn().mockRejectedValue(new Error('down')) };
    const webhook = makeWebhook(http);

    await webhook.notify('message_received', { a: 1 }); // initial attempt fails → enqueued
    const item = webhook.queue[0];
    expect(item.attempts).toBe(0);

    // Advance `now` to each freshly-scheduled backoff boundary.
    await webhook.processQueue(item.nextAttemptAt); // retry 1 fails → attempts 1
    expect(item.attempts).toBe(1);

    await webhook.processQueue(item.nextAttemptAt); // retry 2 fails → attempts 2
    expect(item.attempts).toBe(2);

    await webhook.processQueue(item.nextAttemptAt); // retry 3 fails → attempts 3 → dropped
    expect(webhook.queue).toHaveLength(0);

    // 1 initial + 3 retries = 4 POST attempts.
    expect(http.post).toHaveBeenCalledTimes(4);
  });

  test('(f) backoff windows follow [5s, 15s, 60s]', async () => {
    const http = { post: jest.fn().mockRejectedValue(new Error('down')) };
    const webhook = makeWebhook(http);

    await webhook.notify('e', { a: 1 });
    const item = webhook.queue[0];
    const enqueuedAt = item.nextAttemptAt - 5000; // enqueue scheduled first attempt at +5s

    // now = the scheduled boundary → retry runs, next window is +15s from now.
    await webhook.processQueue(item.nextAttemptAt);
    expect(item.nextAttemptAt).toBe(enqueuedAt + 5000 + 15000);

    await webhook.processQueue(item.nextAttemptAt);
    expect(item.nextAttemptAt).toBe(enqueuedAt + 5000 + 15000 + 60000);
  });

  test('a retried item is removed from the queue once delivery succeeds', async () => {
    const http = { post: jest.fn().mockRejectedValueOnce(new Error('down')) };
    const webhook = makeWebhook(http);

    await webhook.notify('e', { a: 1 }); // fails → enqueued
    expect(webhook.queue).toHaveLength(1);

    http.post.mockResolvedValue({ status: 200 }); // now Rails is back
    await webhook.processQueue(Number.MAX_SAFE_INTEGER);

    expect(webhook.queue).toHaveLength(0);
  });
});
