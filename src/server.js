const express = require('express');
const cors = require('cors');
const createRatingRouter = require('./routes/rating');

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

app.use('/api/v1', createRatingRouter());

module.exports = app;
