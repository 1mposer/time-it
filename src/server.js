const express = require('express');
const createRatingRouter = require('./routes/rating');
const createDevicesRouter = require('./routes/devices');
const createFeedbackRouter = require('./routes/feedback');
const { getCachedWeather } = require('./services/weatherCache');
const {
  createRateLimiter, createProxySelfCheck, rateLimitMode, readLimit,
} = require('./middleware/rateLimit');

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;

// createApp builds the app; `env`, `now` and `log` are injectable for tests.
// The exported default is the production app built from process.env.
function createApp({ env = process.env, now = Date.now, log = console.log } = {}) {
  const app = express();

  // One trusted proxy hop (the platform edge): req.ip is the client address
  // the edge appended to X-Forwarded-For; a client-supplied leading entry is
  // ignored.
  app.set('trust proxy', 1);
  app.disable('x-powered-by');

  // Per-client request limits on the API (GET /health is never limited).
  // Limits run before body parsing, so an over-limit request costs nothing.
  const mode = rateLimitMode(env);
  const limiter = (name, limit, windowMs) => createRateLimiter({ name, limit, windowMs, mode, now, log });
  app.use('/api/v1', createProxySelfCheck({ log }));
  app.use('/api/v1', limiter('api-minute', readLimit('RATE_LIMIT_PER_MINUTE', 120, env), MINUTE_MS));
  app.use('/api/v1', limiter('api-hour', readLimit('RATE_LIMIT_PER_HOUR', 1000, env), HOUR_MS));
  app.use('/api/v1/feedback', limiter('feedback-hour', readLimit('RATE_LIMIT_FEEDBACK_PER_HOUR', 30, env), HOUR_MS));

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

  return app;
}

const app = createApp();

module.exports = app;
module.exports.createApp = createApp;
