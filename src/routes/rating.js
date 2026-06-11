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
      const { forecastStart, hours } = await getWeather(lat, lon);
      const indexedHours = hours.map((h, i) => ({ index: i, ...h }));
      const activities = evaluateAll(hours);
      res.json({ forecastStart, activities, hours: indexedHours });
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
