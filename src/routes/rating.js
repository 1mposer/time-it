const express = require('express');
const { getWeather } = require('../weather');
const { evaluateAll } = require('../decision');

const router = express.Router();

router.get('/rating', async (req, res) => {
  const { lat, lon, timezone = 'UTC' } = req.query;

  if (!lat) return res.status(400).json({ error: 'Missing required parameter: lat' });
  if (!lon) return res.status(400).json({ error: 'Missing required parameter: lon' });

  try {
    const { forecastStart, hours } = await getWeather(lat, lon, timezone);
    const indexedHours = hours.map((h, i) => ({ index: i, ...h }));
    const activities = evaluateAll(hours);
    res.json({ forecastStart, activities, hours: indexedHours });
  } catch (err) {
    if (err.message?.includes('Response status') || err.message?.includes('fetch')) {
      return res.status(502).json({ error: 'Weather data unavailable' });
    }
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
