// Body validation for POST /api/v1/rating (ADR-0005 §6). Atomic and
// structured: every failure across the whole body is collected as
// { path, message } entries — an empty array means valid. Per-activity rules
// live in the shared validateActivities.js; the non-empty activities rule is
// this route's own.

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
