// Device-snapshot registration routes (#6c spec §4, ADR-0006, ADR-0010).
//
// PUT /api/v1/devices/:deviceId — full-snapshot upsert: client-authoritative,
// last-write-wins, no merge. The client re-upserts on ANY change (activity
// edit, home change, APNs token refresh), so the row is always the whole truth.
// Home coordinates are rounded to 2 dp (~1.1 km) at write — the client sends
// full precision, but the stored location must honestly be Coarse (ADR-0010
// granularity ruling); ratings are unaffected because the shared weather cache
// already keys at 2 dp.
// DELETE — opt-out, reinterpreted server-side as DEACTIVATION (ADR-0010
// never-erase rule): blanks apns_token and keeps the row, so activities/home/
// history survive for a re-opt-in. Wire contract unchanged — still 204, still
// idempotent (deactivating a missing row is still 204, and never creates one).
//
// No auth: the deviceId is an unguessable client-minted Keychain UUID and the
// stored data is a weather-preferences snapshot (accepted risk, ADR-0001).

const express = require('express');
const { getCachedWeather } = require('../services/weatherCache');
const defaultDb = require('../db');
const { validateActivities, isFiniteNumber, isNonEmptyString } = require('./validateActivities');
const { sendRouteError } = require('./errorEnvelope');

const APNS_TOKEN_RE = /^[0-9a-fA-F]+$/;

function validateDeviceUpsert(deviceId, body) {
  const errors = [];

  if (body === null || typeof body !== 'object') {
    return [{ path: '', message: 'request body must be a JSON object' }];
  }

  if (!isNonEmptyString(deviceId)) {
    errors.push({ path: 'deviceId', message: 'deviceId is required and must be a non-empty string' });
  }

  if (!isNonEmptyString(body.apnsToken) || !APNS_TOKEN_RE.test(body.apnsToken)) {
    errors.push({ path: 'apnsToken', message: 'apnsToken is required and must be a non-empty hex string' });
  }

  const home = body.home;
  if (home === null || typeof home !== 'object') {
    errors.push({ path: 'home', message: 'home is required and must be an object with lat/lon' });
  } else {
    if (!isFiniteNumber(home.lat) || home.lat < -90 || home.lat > 90) {
      errors.push({ path: 'home.lat', message: 'home.lat is required and must be a number in -90..90' });
    }
    if (!isFiniteNumber(home.lon) || home.lon < -180 || home.lon > 180) {
      errors.push({ path: 'home.lon', message: 'home.lon is required and must be a number in -180..180' });
    }
  }

  // Same ADR-0005 rules as the rating body, via the shared extraction. One
  // deliberate divergence (spec §4): an EMPTY activities[] is VALID here — the
  // client re-upserts on any ActivityStore mutation, and deleting the last
  // Activity must produce a dormant snapshot, not a 400 that strands the stale
  // one (which would keep pushing for deleted Activities until opt-out).
  if (!Array.isArray(body.activities)) {
    errors.push({ path: 'activities', message: 'activities is required and must be an array' });
  } else {
    errors.push(...validateActivities(body.activities));
  }

  return errors;
}

function createDevicesRouter({ getWeather = getCachedWeather, db = defaultDb } = {}) {
  const router = express.Router();

  router.put('/devices/:deviceId', async (req, res) => {
    const { deviceId } = req.params;
    const body = req.body || {};

    const errors = validateDeviceUpsert(deviceId, body);
    if (errors.length > 0) return res.status(400).json({ errors });

    try {
      // Coarse at write (ADR-0010): validation ran on the raw values; storage
      // and the timezone lookup both see the SAME 2 dp values, so the row can
      // never claim a precision its weather lookups didn't use.
      const homeLat = Math.round(body.home.lat * 100) / 100;
      const homeLon = Math.round(body.home.lon * 100) / 100;

      // Resolve the location's IANA zone through the shared weather cache — one
      // (usually cached) call per upsert, which also proves the location is
      // servable before a row exists for it. Provider failure → 502.
      const { timezone } = await getWeather(homeLat, homeLon);

      // last_digest_date is deliberately NOT touched on conflict: a re-upsert
      // (activity edit, token refresh) must not re-arm today's digest.
      await db.query(
        `INSERT INTO devices (device_id, apns_token, home_lat, home_lon, timezone, activities, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, now())
         ON CONFLICT (device_id) DO UPDATE SET
           apns_token = EXCLUDED.apns_token,
           home_lat   = EXCLUDED.home_lat,
           home_lon   = EXCLUDED.home_lon,
           timezone   = EXCLUDED.timezone,
           activities = EXCLUDED.activities,
           updated_at = now()`,
        [deviceId, body.apnsToken, homeLat, homeLon, timezone, JSON.stringify(body.activities)]
      );

      res.status(204).end();
    } catch (err) {
      sendRouteError(res, err);
    }
  });

  router.delete('/devices/:deviceId', async (req, res) => {
    try {
      // Deactivate, never erase (ADR-0010): only the push address lifecycles.
      // An UPDATE matches zero rows for an unknown deviceId — idempotent, and
      // it can never create a row.
      await db.query(
        'UPDATE devices SET apns_token = NULL, updated_at = now() WHERE device_id = $1',
        [req.params.deviceId]
      );
      res.status(204).end();
    } catch (err) {
      sendRouteError(res, err);
    }
  });

  return router;
}

module.exports = createDevicesRouter;
