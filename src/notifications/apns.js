// APNs seam (#6c spec §5). Wraps the apns2 package — which is never imported
// anywhere else; provider-specifics stop at this boundary, exactly like the
// weather adapter. Exports:
//
//   createPushSender({ transport? })  -> { sendPush(apnsToken, { title, body, payload }) }
//   sendPush                          -> the production singleton's send
//   StaleTokenError                   -> typed error for dead tokens
//   buildApnsConfig(env)              -> pure env → config mapping (testable)
//
// The transport contract is `send(apnsToken, { title, body, payload })`,
// throwing errors that carry the APNs `reason` string. The default transport is
// built lazily from apns2 on first send, so requiring this module (or creating
// a sender in tests with a fake transport) never demands APNs env vars.
//
// On APNs 410 Unregistered (or BadDeviceToken) a typed StaleTokenError is
// thrown so callers blank the row's token (never-erase rule, ADR-0010) — dead
// push addresses must not accumulate, but the row itself is kept.

class StaleTokenError extends Error {
  constructor(message) {
    super(message);
    this.name = 'StaleTokenError';
  }
}

const STALE_REASONS = new Set(['Unregistered', 'BadDeviceToken']);

// Pure: env -> apns2 client options. The .p8 ships as env-var PEM CONTENT
// (Railway has no secret files); a pasted key often carries literal "\n"
// escapes, which are normalised back to newlines here.
function buildApnsConfig(env) {
  for (const name of ['APNS_KEY', 'APNS_KEY_ID', 'APNS_TEAM_ID']) {
    if (!env[name]) throw new Error(`${name} environment variable is not set`);
  }
  return {
    team: env.APNS_TEAM_ID,
    keyId: env.APNS_KEY_ID,
    signingKey: env.APNS_KEY.replace(/\\n/g, '\n'),
    // The push topic MUST equal the installed app's bundle identifier —
    // com.timeit.app.dev (the un-suffixed ID is owned by another Apple
    // account and was never ours). APNS_TOPIC overrides for future builds.
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

// Production singleton — the jobs share one client/connection pool.
const { sendPush } = createPushSender();

module.exports = { createPushSender, sendPush, StaleTokenError, buildApnsConfig };
