const express = require('express');
const cors = require('cors');
const createRatingRouter = require('./routes/rating');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use('/api/v1', createRatingRouter());

module.exports = app;
