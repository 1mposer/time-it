// Beta feedback route: POST /api/v1/feedback.
//
// The lowest-friction suggestion box for test builds: the app POSTs free text
// plus build metadata, the row lands in Postgres, the owner reads it with SQL —
// no mail client, no TestFlight detour. `build` (CFBundleVersion) is stored
// alongside the app/iOS versions so every suggestion reads in the context of
// the exact build that produced it.
//
// No auth (same accepted-risk posture as the device routes, ADR-0001). The
// abuse surface is bounded by the message length cap, the express.json() body
// limit, and a per-device daily ceiling keyed on the same Keychain install
// UUID the push path uses. No FK to devices — feedback must not require push
// opt-in.

const express = require('express');
const defaultDb = require('../db');
const { isNonEmptyString } = require('./validateActivities');
const { errorBody, sendRouteError } = require('./errorEnvelope');

const MAX_MESSAGE_CHARS = 1000;
const MAX_FIELD_CHARS = 64;
const MAX_PER_DEVICE_PER_DAY = 20;

const META_FIELDS = ['deviceId', 'appVersion', 'build', 'iosVersion'];

function validateFeedback(body) {
  if (body === null || typeof body !== 'object') {
    return [{ path: '', message: 'request body must be a JSON object' }];
  }

  const errors = [];

  if (!isNonEmptyString(body.message) || body.message.trim().length === 0) {
    errors.push({ path: 'message', message: 'message is required and must be a non-empty string' });
  } else if (body.message.length > MAX_MESSAGE_CHARS) {
    errors.push({ path: 'message', message: `message must be at most ${MAX_MESSAGE_CHARS} characters` });
  }

  for (const field of META_FIELDS) {
    const value = body[field];
    if (!isNonEmptyString(value)) {
      errors.push({ path: field, message: `${field} is required and must be a non-empty string` });
    } else if (value.length > MAX_FIELD_CHARS) {
      errors.push({ path: field, message: `${field} must be at most ${MAX_FIELD_CHARS} characters` });
    }
  }

  return errors;
}

function createFeedbackRouter({ db = defaultDb } = {}) {
  const router = express.Router();

  router.post('/feedback', async (req, res) => {
    const body = req.body || {};

    const errors = validateFeedback(body);
    if (errors.length > 0) return res.status(400).json({ errors });

    try {
      // Per-device rolling-24h ceiling — the only throttle an unauthenticated
      // endpoint needs at beta scale.
      const { rows } = await db.query(
        `SELECT count(*)::int AS count FROM suggestions
         WHERE device_id = $1 AND created_at > now() - interval '24 hours'`,
        [body.deviceId]
      );
      if (Number(rows[0].count) >= MAX_PER_DEVICE_PER_DAY) {
        return res.status(429).json(errorBody('Too many suggestions today — try again tomorrow'));
      }

      await db.query(
        `INSERT INTO suggestions (device_id, message, app_version, build, ios_version)
         VALUES ($1, $2, $3, $4, $5)`,
        [body.deviceId, body.message.trim(), body.appVersion, body.build, body.iosVersion]
      );

      res.status(204).end();
    } catch (err) {
      sendRouteError(res, err);
    }
  });

  return router;
}

module.exports = createFeedbackRouter;
