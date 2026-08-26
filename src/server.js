const express = require('express');
const cors = require('cors');
const createRatingRouter = require('./routes/rating');
const createDevicesRouter = require('./routes/devices');
const createFeedbackRouter = require('./routes/feedback');
const { getCachedWeather } = require('./services/weatherCache');

const app = express();
app.use(cors());
app.use(express.json());

// express.json() failures (malformed JSON, oversized body) are thrown before
// any route — map them to the uniform { errors } envelope (ADR-0005 §6) here.
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

// /rating shares the same 60-min weather cache instance as the push jobs.
app.use('/api/v1', createRatingRouter({ getWeather: getCachedWeather }));
app.use('/api/v1', createDevicesRouter());
app.use('/api/v1', createFeedbackRouter());

module.exports = app;
