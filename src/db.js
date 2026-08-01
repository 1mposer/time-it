// Postgres layer (#6c spec §3, ADR-0006). Railway injects DATABASE_URL.
//
// Deliberately thin: `query` is a pool passthrough and `initDb()` is an
// idempotent CREATE TABLE IF NOT EXISTS — no migration framework at this
// scale. The pool is created lazily so merely requiring this module (e.g. from
// the devices router's default DI wiring in tests) never demands a DATABASE_URL
// or opens a connection; only the first query does.
//
// The push path's ONLY state lives here (the /rating path stays stateless):
// `devices` (one row per opted-in install) and `notification_state` (#6d — the
// detector's one-alert-per-(device, activity, bucket) dedup ledger, cascading
// away with its device row). `activities` is the validated ADR-0005 snapshot as
// JSONB; `last_digest_date` is the sent-today marker the digest job compares
// against device-local today (DATE — the pg driver returns it as a JS Date
// object; see the type-trap note in src/jobs/dailyDigest.js).

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
      apns_token       TEXT NOT NULL,
      home_lat         DOUBLE PRECISION NOT NULL,
      home_lon         DOUBLE PRECISION NOT NULL,
      timezone         TEXT NOT NULL,
      activities       JSONB NOT NULL,
      last_digest_date DATE,
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
  await query(`
    CREATE TABLE IF NOT EXISTS notification_state (
      device_id   TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
      activity_id TEXT NOT NULL,
      bucket_date DATE NOT NULL,
      notified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (device_id, activity_id, bucket_date)
    );
  `);
}

module.exports = { query, initDb };
