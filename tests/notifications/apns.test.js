const test = require('node:test');
const assert = require('node:assert/strict');

const { createPushSender, StaleTokenError, buildApnsConfig } = require('../../src/notifications/apns');

// --- seam contract with a stubbed transport ---
test('sendPush passes the token and message through the transport', async () => {
  const sent = [];
  const transport = { send: async (token, message) => { sent.push({ token, message }); } };
  const { sendPush } = createPushSender({ transport });
  const message = { title: 'Daily Digest', body: 'Cycling: Perfect 7–10am', payload: { type: 'dailyDigest' } };
  await sendPush('a1b2c3', message);
  assert.deepStrictEqual(sent, [{ token: 'a1b2c3', message }]);
});

test('APNs Unregistered / BadDeviceToken → typed StaleTokenError', async () => {
  for (const reason of ['Unregistered', 'BadDeviceToken']) {
    const transport = { send: async () => { const e = new Error('gone'); e.reason = reason; throw e; } };
    const { sendPush } = createPushSender({ transport });
    await assert.rejects(() => sendPush('t', { title: 't', body: 'b' }), (err) => {
      assert.ok(err instanceof StaleTokenError);
      assert.equal(err.name, 'StaleTokenError');
      return true;
    });
  }
});

test('any other APNs failure is rethrown as-is, not swallowed into StaleTokenError', async () => {
  const original = new Error('rate limited');
  original.reason = 'TooManyRequests';
  const transport = { send: async () => { throw original; } };
  const { sendPush } = createPushSender({ transport });
  await assert.rejects(() => sendPush('t', { title: 't', body: 'b' }), (err) => err === original);
});

// --- config from env ---
test('buildApnsConfig maps env to the apns2 options with topic com.timeit.app', () => {
  const config = buildApnsConfig({
    APNS_KEY: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----',
    APNS_KEY_ID: 'KEYID12345',
    APNS_TEAM_ID: 'TEAM123456',
  });
  assert.equal(config.team, 'TEAM123456');
  assert.equal(config.keyId, 'KEYID12345');
  assert.equal(config.defaultTopic, 'com.timeit.app');
  assert.equal(config.signingKey, '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----',
    'literal \\n escapes from a pasted env var are normalised to newlines');
});

test('host is sandbox by default and production only when NODE_ENV=production', () => {
  const base = { APNS_KEY: 'k', APNS_KEY_ID: 'i', APNS_TEAM_ID: 't' };
  assert.equal(buildApnsConfig(base).host, 'api.sandbox.push.apple.com');
  assert.equal(buildApnsConfig({ ...base, NODE_ENV: 'development' }).host, 'api.sandbox.push.apple.com');
  assert.equal(buildApnsConfig({ ...base, NODE_ENV: 'production' }).host, 'api.push.apple.com');
});

test('a missing APNs env var throws with the variable named', () => {
  const base = { APNS_KEY: 'k', APNS_KEY_ID: 'i', APNS_TEAM_ID: 't' };
  for (const name of ['APNS_KEY', 'APNS_KEY_ID', 'APNS_TEAM_ID']) {
    const env = { ...base };
    delete env[name];
    assert.throws(() => buildApnsConfig(env), new RegExp(name));
  }
});
