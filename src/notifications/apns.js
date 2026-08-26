// APNs seam — apns2 is imported nowhere else. Exposes createPushSender (for
// tests), the production sendPush singleton, StaleTokenError (dead token —
// callers blank the row's token, keep the row; ADR-0010 never-erase), and
// buildApnsConfig (pure env → config). The real transport is built lazily on
// first send, so requiring this module never demands APNs env vars.

class StaleTokenError extends Error {
  constructor(message) {
    super(message);
    this.name = 'StaleTokenError';
  }
}

const STALE_REASONS = new Set(['Unregistered', 'BadDeviceToken']);

// Pure env → apns2 client options. APNS_KEY is .p8 PEM content (literal "\n"
// escapes are normalised); the push topic must equal the installed app's
// bundle identifier — com.timeit.app.dev (the un-suffixed com.timeit.app is
// owned by another Apple account and was never ours).
function buildApnsConfig(env) {
  for (const name of ['APNS_KEY', 'APNS_KEY_ID', 'APNS_TEAM_ID']) {
    if (!env[name]) throw new Error(`${name} environment variable is not set`);
  }
  return {
    team: env.APNS_TEAM_ID,
    keyId: env.APNS_KEY_ID,
    signingKey: env.APNS_KEY.replace(/\\n/g, '\n'),
    defaultTopic: env.APNS_TOPIC || 'com.timeit.app.dev',
    host: env.NODE_ENV === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com',
  };
}

function createApns2Transport() {
  const { ApnsClient, Notification } = require('apns2');
  const client = new ApnsClient(buildApnsConfig(process.env));
  return {
    send: (apnsToken, { title, body, payload }) =>
      client.send(new Notification(apnsToken, { alert: { title, body }, data: payload })),
  };
}

function createPushSender({ transport } = {}) {
  async function sendPush(apnsToken, message) {
    if (!transport) transport = createApns2Transport();
    try {
      await transport.send(apnsToken, message);
    } catch (err) {
      if (err && STALE_REASONS.has(err.reason)) {
        throw new StaleTokenError(`APNs token is stale (${err.reason})`);
      }
      throw err;
    }
  }
  return { sendPush };
}

// Production singleton — the jobs share one client.
const { sendPush } = createPushSender();

module.exports = { createPushSender, sendPush, StaleTokenError, buildApnsConfig };
