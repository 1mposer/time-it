const express = require('express');
const { getWeather: defaultGetWeather } = require('../weather');
const { evaluateAll: defaultEvaluateAll } = require('../decision');
const { UpstreamError } = require('../weather/UpstreamError');

function createRatingRouter({ getWeather = defaultGetWeather, evaluateAll = defaultEvaluateAll } = {}) {
  const router = express.Router();

  router.get('/rating', async (req, res) => {
    const { lat, lon } = req.query;

    if (!lat) return res.status(400).json({ error: 'Missing required parameter: lat' });
    if (!lon) return res.status(400).json({ error: 'Missing required parameter: lon' });

    try {
      const { forecastStart, timezone, hours } = await getWeather(lat, lon);
      const activities = evaluateAll(hours);
      // Wire shape (ADR-0004): index first; the internal localDay tag is stripped
      // (the client derives day membership from forecastStart + timezone + index).
      const indexedHours = hours.map(({ localDay, ...h }, i) => ({ index: i, ...h }));
      res.json({ forecastStart, timezone, activities, hours: indexedHours });
    } catch (err) {
      if (err instanceof UpstreamError) {
        return res.status(502).json({ error: 'Weather data unavailable' });
      }
      console.error(err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}

module.exports = createRatingRouter;
