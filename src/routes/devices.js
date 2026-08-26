// Device-snapshot routes for the push path (ADR-0006).
// PUT /api/v1/devices/:deviceId — full-snapshot upsert, last-write-wins. Home
// coords are rounded to 2 dp at write (ADR-0010 coarse-location ruling);
// last_digest_date survives re-upserts.
// DELETE /api/v1/devices/:deviceId — deactivate: blanks the APNs token but
// keeps the row (ADR-0010 never-erase). Idempotent, never creates a row. Both
// return 204. No auth — the deviceId is an unguessable client-minted UUID
// (accepted risk, ADR-0001).

const express = require('express');
const { getCachedWeather } = require('../services/weatherCache');
const defaultDb = require('../db');
const { validateActivities, isFiniteNumber, isNonEmptyString } = require('./validateActivities');
const { sendRouteError } = require('./errorEnvelope');

const APNS_TOKEN_RE = /^[0-9a-fA-F]+$/;

// Returns { path, message } errors; empty array = valid. Same shared ADR-0005
// rules as the rating body, with one divergence: an empty activities[] is
// valid here (a dormant snapshot).
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
      const homeLat = Math.round(body.home.lat * 100) / 100;
      const homeLon = Math.round(body.home.lon * 100) / 100;

      const { timezone } = await getWeather(homeLat, homeLon);

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
