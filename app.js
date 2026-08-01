require('dotenv').config();
const app = require('./src/server');
const { initDb } = require('./src/db');
const { startJobs } = require('./src/jobs');

const PORT = process.env.PORT || 3000;

// initDb is idempotent (CREATE TABLE IF NOT EXISTS); a failure exits non-zero
// so Railway restarts the service instead of running push-less. GET /health
// stays DB-independent — liveness never depends on Postgres. Jobs start only
// after listen, on the single always-on replica (ADR-0006).
initDb()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`time-it listening on port ${PORT}`);
      startJobs();
      console.log('in-process jobs started (daily digest, hourly pass)');
    });
  })
  .catch((err) => {
    console.error('database init failed', err);
    process.exit(1);
  });
