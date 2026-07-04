const createApp = require('../src/app');
const SessionService = require('../src/session');
const { silentLogger, testConfig, makeMockClient } = require('./helpers');

// Uses Node's built-in fetch (Node 18+) against an ephemeral-port server —
// no supertest dependency needed.
function listen(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, () => {
      const { port } = server.address();
      resolve({ server, base: `http://127.0.0.1:${port}` });
    });
  });
}

function makeSession(client) {
  const webhook = { notify: jest.fn().mockResolvedValue(true) };
  return new SessionService({
    config: testConfig,
    logger: silentLogger,
    webhook,
    clientFactory: () => client || makeMockClient(),
    sleep: () => Promise.resolve(),
  });
}

const authed = { Authorization: 'Bearer test-token', 'Content-Type': 'application/json' };

describe('HTTP API', () => {
  let server;
  let base;

  afterEach(() => {
    if (server) server.close();
    server = null;
  });

  test('(e) /health needs no auth and reports wa_status + real state', async () => {
    const session = makeSession();
    session.status = 'connected';
    session.phoneNumber = '5511999999999';
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/health`); // no Authorization header
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toMatchObject({ status: 'ok', wa_status: 'connected', wa_phone: '5511999999999' });
  });

  test('(e) protected routes reject a missing token with 401', async () => {
    const session = makeSession();
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/session/status`); // no token
    expect(res.status).toBe(401);
  });

  test('(e) protected routes reject a bad token with 401', async () => {
    const session = makeSession();
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/session/status`, {
      headers: { Authorization: 'Bearer wrong' },
    });
    expect(res.status).toBe(401);
  });

  test('(d) POST /messages returns 409 when not connected', async () => {
    const session = makeSession();
    session.status = 'qr_pending';
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/messages`, {
      method: 'POST',
      headers: authed,
      body: JSON.stringify({ phone_number: '5511988887777', message: 'oi' }),
    });

    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: 'not_connected' });
  });

  test('(d) POST /messages sends via client with the @c.us chatId when connected', async () => {
    const client = makeMockClient();
    const session = makeSession(client);
    await session.initialize();
    session.status = 'connected';
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/messages`, {
      method: 'POST',
      headers: authed,
      body: JSON.stringify({ phone_number: '+55 11 98888-7777', message: 'confirmado ✅' }),
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ id: 'SENT_ID', timestamp: 1700000000, ack: 1 });
    expect(client.sendMessage).toHaveBeenCalledWith('5511988887777@c.us', 'confirmado ✅');
  });

  test('POST /messages validates required fields with 400', async () => {
    const session = makeSession();
    session.status = 'connected';
    ({ server, base } = await listen(createApp({ config: testConfig, session })));

    const res = await fetch(`${base}/messages`, {
      method: 'POST',
      headers: authed,
      body: JSON.stringify({ phone_number: '5511988887777' }), // no message
    });
    expect(res.status).toBe(400);
  });
});
