const { EventEmitter } = require('events');

/** Silent logger so tests don't spam the console. */
const silentLogger = {
  info: () => {},
  error: () => {},
  warn: () => {},
  debug: () => {},
};

const testConfig = {
  port: 0,
  nodeEnv: 'test',
  railsWebhookUrl: 'http://rails.test/api/whatsapp/webhook',
  railsApiToken: 'test-token',
  clientId: 'azulzin-main',
  sessionDataPath: './.wwebjs_auth',
  sendMinIntervalMs: 0,
  mediaMaxBytes: 16 * 1024 * 1024,
};

/** A mock wwebjs Client: an EventEmitter with the methods SessionService calls. */
function makeMockClient(overrides = {}) {
  const client = new EventEmitter();
  client.initialize = jest.fn().mockResolvedValue(undefined);
  client.destroy = jest.fn().mockResolvedValue(undefined);
  client.getState = jest.fn().mockResolvedValue('CONNECTED');
  client.sendMessage = jest
    .fn()
    .mockResolvedValue({ id: { id: 'SENT_ID' }, timestamp: 1700000000, ack: 1 });
  client.getChatById = jest
    .fn()
    .mockResolvedValue({ sendStateTyping: jest.fn().mockResolvedValue(undefined) });
  client.info = { wid: { user: '5511999999999' }, platform: 'android', pushname: 'azulzin' };
  client.authStrategy = { logout: jest.fn().mockResolvedValue(undefined) };
  return Object.assign(client, overrides);
}

/** A mock inbound message from a private (@c.us) contact. */
function makeMockMessage(overrides = {}) {
  return {
    id: { id: 'HASH123', _serialized: 'true_5511988887777@c.us_3EB0ABCDEF' },
    from: '5511988887777@c.us',
    to: '5511999999999@c.us',
    body: 'gastei 50 no mercado',
    timestamp: 2000,
    hasMedia: false,
    type: 'chat',
    getContact: async () => ({ pushname: 'Joao', name: 'Joao Silva', number: '5511988887777' }),
    downloadMedia: async () => null,
    ...overrides,
  };
}

module.exports = { silentLogger, testConfig, makeMockClient, makeMockMessage };
