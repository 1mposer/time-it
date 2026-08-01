const express = require('express');
const { getWeather: defaultGetWeather } = require('../weather');
const { evaluateAll: defaultEvaluateAll } = require('../decision');
const { validateRatingRequest } = require('./validateRatingRequest');
const { sendRouteError } = require('./errorEnvelope');

function createRatingRouter({ getWeather = defaultGetWeather, evaluateAll = defaultEvaluateAll } = {}) {
  const router = express.Router();

  // POST (ADR-0005): the activity-agnostic engine needs the caller to SEND the
  // profiles it evaluates, so lat/lon + activities[] move into the JSON body.
  router.post('/rating', async (req, res) => {
    const body = req.body || {};

    // Validate the body BEFORE touching the provider — a malformed request must not
    // spend a getWeather call. Atomic: any error rejects the whole request as 400.
    const errors = validateRatingRequest(body);
    if (errors.length > 0) return res.status(400).json({ errors });

    const { lat, lon, activities } = body;

    try {
      // No timezone in the request — the location's zone is resolved server-side
      // from lat/lon (ADR-0005); getWeather takes exactly (lat, lon).
      const { forecastStart, timezone, hours } = await getWeather(lat, lon);
      const resultActivities = evaluateAll(hours, activities);
      // Wire shape (ADR-0004): index first; internal localDay/localHour tags are
      // stripped (the client derives day/clock from forecastStart + timezone + index).
      const indexedHours = hours.map(({ localDay, localHour, ...h }, i) => ({ index: i, ...h }));
      res.json({ forecastStart, timezone, activities: resultActivities, hours: indexedHours });
    } catch (err) {
      sendRouteError(res, err);
    }
  });

  return router;
}

module.exports = createRatingRouter;
