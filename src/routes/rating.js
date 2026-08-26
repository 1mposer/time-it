// Rating route: POST /api/v1/rating (ADR-0005) — validates the body before any
// provider call, then getWeather → evaluateAll → the wire shape (ADR-0004:
// internal localDay/localHour tags stripped, index prepended).

const express = require('express');
const { getWeather: defaultGetWeather } = require('../weather');
const { evaluateAll: defaultEvaluateAll } = require('../decision');
const { validateRatingRequest } = require('./validateRatingRequest');
const { sendRouteError } = require('./errorEnvelope');

function createRatingRouter({ getWeather = defaultGetWeather, evaluateAll = defaultEvaluateAll } = {}) {
  const router = express.Router();

  router.post('/rating', async (req, res) => {
    const body = req.body || {};

    const errors = validateRatingRequest(body);
    if (errors.length > 0) return res.status(400).json({ errors });

    const { lat, lon, activities } = body;

    try {
      const { forecastStart, timezone, hours } = await getWeather(lat, lon);
      const resultActivities = evaluateAll(hours, activities);
      const indexedHours = hours.map(({ localDay, localHour, ...h }, i) => ({ index: i, ...h }));
      res.json({ forecastStart, timezone, activities: resultActivities, hours: indexedHours });
    } catch (err) {
      sendRouteError(res, err);
    }
  });

  return router;
}

module.exports = createRatingRouter;
