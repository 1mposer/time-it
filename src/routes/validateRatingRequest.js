// Request-body validation for POST /api/v1/rating (ADR-0005 §6).
//
// Validation is ATOMIC and STRUCTURED: every failure across the whole body is
// collected (never first-wins) and returned as an array of { path, message }, so
// an atomic-rejected client can fix everything and resubmit once. An empty array
// means the body is valid. The route maps a non-empty result to a single 400 —
// one invalid activity rejects the WHOLE request (no partial evaluation), so the
// success shape never carries error state.
//
// The per-activity rules (including the load-bearing coming-soon/unknown metric
// reject) live in the shared validateActivities.js — the device-snapshot upsert
// (#6c) validates with the same rules. The NON-EMPTY activities rule is this
// route's own: rating an empty list is meaningless, while an empty device
// snapshot is a valid dormant registration.

const { validateActivities, isFiniteNumber, MAX_ACTIVITIES } = require('./validateActivities');

const LAT_MIN = -90, LAT_MAX = 90;
const LON_MIN = -180, LON_MAX = 180;

function validateRatingRequest(body) {
  const errors = [];

  if (body === null || typeof body !== 'object') {
    return [{ path: '', message: 'request body must be a JSON object' }];
  }

  if (!isFiniteNumber(body.lat) || body.lat < LAT_MIN || body.lat > LAT_MAX) {
    errors.push({ path: 'lat', message: `lat is required and must be a number in ${LAT_MIN}..${LAT_MAX}` });
  }
  if (!isFiniteNumber(body.lon) || body.lon < LON_MIN || body.lon > LON_MAX) {
    errors.push({ path: 'lon', message: `lon is required and must be a number in ${LON_MIN}..${LON_MAX}` });
  }

  const activities = body.activities;
  if (!Array.isArray(activities) || activities.length === 0) {
    errors.push({ path: 'activities', message: 'activities is required and must be a non-empty array' });
  } else {
    errors.push(...validateActivities(activities));
  }

  return errors;
}

module.exports = { validateRatingRequest, MAX_ACTIVITIES };
