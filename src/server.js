const express = require('express');
const cors = require('cors');
const createRatingRouter = require('./routes/rating');
const createDevicesRouter = require('./routes/devices');
const { getCachedWeather } = require('./services/weatherCache');

const app = express();
app.use(cors());
app.use(express.json());

// Body-parser failures (malformed JSON, oversized payload) are thrown by
// express.json() BEFORE the route runs, so the route's own try/catch never sees
// them. Map them to the same uniform { errors: [{ message }] } envelope the iOS
// decoder expects on EVERY error code (ADR-0005 §6) — otherwise Express's default
// handler renders an HTML stack trace the client can't decode.
app.use((err, _req, res, next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ errors: [{ message: 'Malformed JSON in request body' }] });
  }
  if (err.type === 'entity.too.large') {
    return res.status(413).json({ errors: [{ message: 'Request body too large' }] });
  }
  return next(err);
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// /rating reads through the shared 60-min weather cache (#6c spec §6 amendment
// 2026-07-20) — same cache instance as the push jobs and the device upsert. The
// wire contract is byte-identical; only the provider fetch is memoized.
app.use('/api/v1', createRatingRouter({ getWeather: getCachedWeather }));
// Push-path registration (#6c, ADR-0006): the devices router defaults its own
// getWeather to the same shared cache; db defaults to src/db.js (lazy pool).
app.use('/api/v1', createDevicesRouter());

module.exports = app;
