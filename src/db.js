// Postgres layer over DATABASE_URL (ADR-0006). `query` is a lazy pool
// passthrough (no connection until the first query) and `initDb()` idempotently
// creates the tables: devices (one row per opted-in install; NULL apns_token =
// deactivated for push — rows are never deleted, ADR-0010 never-erase),
// notification_state (the detector's dedup ledger), and suggestions (beta
// feedback inbox — deliberately no FK to devices).

const { Pool } = require('pg');

let pool;
function getPool() {
  if (!pool) {
    pool = new Pool({ connectionString: process.env.DATABASE_URL });
  }
  return pool;
}

function query(text, params) {
  return getPool().query(text, params);
}

async function initDb() {
  await query(`
    CREATE TABLE IF NOT EXISTS devices (
      device_id        TEXT PRIMARY KEY,
      apns_token       TEXT,
      home_lat         DOUBLE PRECISION NOT NULL,
      home_lon         DOUBLE PRECISION NOT NULL,
      timezone         TEXT NOT NULL,
      activities       JSONB NOT NULL,
      last_digest_date DATE,
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  // Re-runnable conversion of the pre-ADR-0010 live table (apns_token was NOT NULL).
  await query('ALTER TABLE devices ALTER COLUMN apns_token DROP NOT NULL;');
  await query(`
    CREATE TABLE IF NOT EXISTS notification_state (
      device_id   TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
      activity_id TEXT NOT NULL,
      bucket_date DATE NOT NULL,
      notified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (device_id, activity_id, bucket_date)
    );
  `);
  await query(`
    CREATE TABLE IF NOT EXISTS suggestions (
      id          BIGSERIAL PRIMARY KEY,
      device_id   TEXT NOT NULL,
      message     TEXT NOT NULL,
      app_version TEXT NOT NULL,
      build       TEXT NOT NULL,
      ios_version TEXT NOT NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS suggestions_device_created_idx
      ON suggestions (device_id, created_at);
  `);
}

module.exports = { query, initDb };
