const SessionService = require('../src/session');
const { silentLogger, testConfig, makeMockClient, makeMockMessage } = require('./helpers');

function makeSession(overrides = {}) {
  const webhook = { notify: jest.fn().mockResolvedValue(true) };
  const client = overrides.client || makeMockClient();
  const session = new SessionService({
    config: testConfig,
    logger: silentLogger,
    webhook,
    clientFactory: () => client,
    sleep: () => Promise.resolve(), // no real delays
  });
  return { session, webhook, client };
}

describe('SessionService inbound message handling', () => {
  test('(a) normalizes an inbound message into a message_received webhook payload', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000; // message.timestamp (2000) is newer → accepted

    await session._handleMessage(makeMockMessage());

    expect(webhook.notify).toHaveBeenCalledTimes(1);
    const [event, data] = webhook.notify.mock.calls[0];
    expect(event).toBe('message_received');
    expect(data).toMatchObject({
      message_id: 'HASH123',
      message_id_serialized: 'true_5511988887777@c.us_3EB0ABCDEF', // idempotency key
      from: '5511988887777@c.us',
      to: '5511999999999@c.us',
      body: 'gastei 50 no mercado',
      timestamp: 2000,
      has_media: false,
      type: 'chat',
      contact_name: 'Joao',
      contact_number: '5511988887777',
      media: null,
    });
  });

  test('(a2) downloads media and forwards it as base64', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000;
    const message = makeMockMessage({
      hasMedia: true,
      type: 'image',
      downloadMedia: async () => ({ mimetype: 'image/jpeg', data: 'QkFTRTY0', filename: 'r.jpg' }),
    });

    await session._handleMessage(message);

    const [, data] = webhook.notify.mock.calls[0];
    expect(data.media).toEqual({ mimetype: 'image/jpeg', data: 'QkFTRTY0', filename: 'r.jpg' });
    expect(data.media_too_large).toBe(false);
  });

  test('(a3) skips oversized media without downloading and flags media_too_large', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000;
    const downloadMedia = jest.fn(); // must NOT be called
    const message = makeMockMessage({
      hasMedia: true,
      type: 'document',
      _data: { size: testConfig.mediaMaxBytes + 1 },
      downloadMedia,
    });

    await session._handleMessage(message);

    expect(downloadMedia).not.toHaveBeenCalled();
    const [, data] = webhook.notify.mock.calls[0];
    expect(data.media).toBeNull();
    expect(data.media_too_large).toBe(true);
  });

  test('(a4) media at the cap still downloads normally', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000;
    const message = makeMockMessage({
      hasMedia: true,
      type: 'image',
      _data: { size: testConfig.mediaMaxBytes },
      downloadMedia: async () => ({ mimetype: 'image/jpeg', data: 'QkFTRTY0', filename: 'r.jpg' }),
    });

    await session._handleMessage(message);

    const [, data] = webhook.notify.mock.calls[0];
    expect(data.media).toEqual({ mimetype: 'image/jpeg', data: 'QkFTRTY0', filename: 'r.jpg' });
    expect(data.media_too_large).toBe(false);
  });

  test('(b) drops historical messages older than connectedAt', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 5000; // message.timestamp (1000) is older → dropped

    await session._handleMessage(makeMockMessage({ timestamp: 1000 }));

    expect(webhook.notify).not.toHaveBeenCalled();
  });

  test('(c) drops non-@c.us senders (groups, broadcast, status)', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000;

    await session._handleMessage(makeMockMessage({ from: '5511988887777-1234@g.us' }));
    await session._handleMessage(makeMockMessage({ from: 'status@broadcast' }));

    expect(webhook.notify).not.toHaveBeenCalled();
  });

  test('a thrown error inside the handler never propagates (client stays alive)', async () => {
    const { session, webhook } = makeSession();
    session.connectedAt = 1000;
    const message = makeMockMessage({
      getContact: async () => {
        throw new Error('boom');
      },
    });

    await expect(session._handleMessage(message)).resolves.toBeUndefined();
    expect(webhook.notify).not.toHaveBeenCalled();
  });
});

describe('SessionService send', () => {
  test('(d-service) throws NOT_CONNECTED when the session is not connected', async () => {
    const { session } = makeSession();
    session.status = 'qr_pending';

    await expect(session.sendMessage('5511988887777', 'oi')).rejects.toMatchObject({
      code: 'NOT_CONNECTED',
    });
  });

  test('builds the @c.us chatId (stripping non-digits) and calls client.sendMessage', async () => {
    const { session, client } = makeSession();
    await session.initialize(); // attaches the mock client
    session.status = 'connected';

    const result = await session.sendMessage('+55 (11) 98888-7777', 'olá');

    expect(client.getChatById).toHaveBeenCalledWith('5511988887777@c.us');
    expect(client.sendMessage).toHaveBeenCalledWith('5511988887777@c.us', 'olá');
    expect(result).toEqual({ id: 'SENT_ID', timestamp: 1700000000, ack: 1 });
  });
});

describe('SessionService zombie guard', () => {
  test('flips connected → disconnected and notifies when getState() is not CONNECTED', async () => {
    const client = makeMockClient({ getState: jest.fn().mockResolvedValue('UNPAIRED') });
    const { session, webhook } = makeSession({ client });
    await session.initialize(); // attaches the mock client
    session.status = 'connected';

    await session._reconcileState();

    expect(session.status).toBe('disconnected');
    expect(webhook.notify).toHaveBeenCalledWith('disconnected', { reason: 'zombie_state_check' });
  });

  test('does nothing while the real state is CONNECTED', async () => {
    const { session, webhook } = makeSession();
    await session.initialize(); // default mock getState() resolves 'CONNECTED'
    session.status = 'connected';

    await session._reconcileState();

    expect(session.status).toBe('connected');
    expect(webhook.notify).not.toHaveBeenCalled();
  });

  test('promotes authenticated → connected when getState() is CONNECTED but `ready` never fired', async () => {
    const { session, webhook } = makeSession(); // default mock getState() resolves 'CONNECTED'
    await session.initialize();
    session.status = 'authenticated'; // stuck: authenticated but `ready` was never emitted

    await session._reconcileState();

    expect(session.status).toBe('connected');
    expect(typeof session.connectedAt).toBe('number');
    expect(webhook.notify).toHaveBeenCalledWith(
      'connected',
      expect.objectContaining({ phone_number: '5511999999999' })
    );
  });
});

describe('SessionService event wiring', () => {
  test('ready event sets connected status, phone, connectedAt and notifies', async () => {
    const { session, webhook, client } = makeSession();
    await session.initialize();

    client.emit('ready');
    await new Promise((r) => setImmediate(r)); // let the async handler run

    expect(session.status).toBe('connected');
    expect(session.phoneNumber).toBe('5511999999999');
    expect(typeof session.connectedAt).toBe('number');
    expect(webhook.notify).toHaveBeenCalledWith('connected', {
      phone_number: '5511999999999',
      platform: 'android',
      pushname: 'azulzin',
    });
  });
});
