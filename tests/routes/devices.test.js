const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createDevicesRouter = require('../../src/routes/devices');
const { UpstreamError } = require('../../src/weather/UpstreamError');

// Stateful fake db: interprets exactly the queries the router issues, storing
// rows the way the pg driver would return them (activities parsed from JSONB,
// last_digest_date as a JS Date or null).
function makeFakeDb() {
  const rows = new Map(); // device_id -> row
  const queries = [];
  return {
    rows,
    queries,
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('INSERT INTO devices')) {
        const [deviceId, apnsToken, lat, lon, timezone, activitiesJson] = params;
        const existing = rows.get(deviceId);
        rows.set(deviceId, {
          device_id: deviceId,
          apns_token: apnsToken,
          home_lat: lat,
          home_lon: lon,
          timezone,
          activities: JSON.parse(activitiesJson),
          last_digest_date: existing ? existing.last_digest_date : null,
          updated_at: new Date(),
        });
        return { rows: [] };
      }
      if (text.startsWith('UPDATE devices SET apns_token = NULL')) {
        // Deactivate (ADR-0010): an UPDATE matches zero rows for an unknown
        // device_id — it must never create one.
        const row = rows.get(params[0]);
        if (row) {
          row.apns_token = null;
          row.updated_at = new Date();
        }
        return { rows: [] };
      }
      throw new Error(`fake db: unexpected query: ${text}`);
    },
  };
}

const DUBAI_WEATHER = { forecastStart: '2026-08-01T02:00:00Z', timezone: 'Asia/Dubai', hours: [] };
const happyGetWeather = async () => DUBAI_WEATHER;

function makeApp({ getWeather = happyGetWeather, db = makeFakeDb() } = {}) {
  const app = express();
  app.use(express.json());
  app.use('/api/v1', createDevicesRouter({ getWeather, db }));
  return { app, db };
}

const DEVICE_ID = '9f3a0c1e-4b7d-4a2e-8f6c-1d2e3f4a5b6c';
const ACTIVITIES = [
  { id: 'cycling', label: 'Cycling', displayMetrics: ['temp', 'windSpeed'],
    thresholds: { temp: { min: 15, max: 35, required: true }, windSpeed: { max: 15, required: false } } },
  { id: 'star', label: 'Stargazing', displayMetrics: ['temp', 'cloudCover'],
    thresholds: { cloudCover: { max: 20, required: true } },
    window: { startHour: 22, endHour: 2 } },
];
function validBody(activities = ACTIVITIES) {
  return { apnsToken: 'a1b2c3d4e5f6', home: { lat: 25.1627, lon: 55.2077 }, activities };
}

const put = (app, body, id = DEVICE_ID) => supertest(app).put(`/api/v1/devices/${id}`).send(body);

// --- upsert happy path ---
test('PUT upserts the snapshot: 204, row shape, server-resolved timezone stored', async () => {
  const { app, db } = makeApp();
  const res = await put(app, validBody());
  assert.equal(res.status, 204);
  const row = db.rows.get(DEVICE_ID);
  assert.ok(row, 'row exists');
  assert.equal(row.apns_token, 'a1b2c3d4e5f6');
  // Stored at 2 dp, not the request's 25.1627/55.2077 (ADR-0010 Coarse ruling).
  assert.equal(row.home_lat, 25.16);
  assert.equal(row.home_lon, 55.21);
  assert.equal(row.timezone, 'Asia/Dubai', 'IANA zone resolved server-side at upsert');
  assert.deepStrictEqual(row.activities, ACTIVITIES);
  assert.equal(row.last_digest_date, null);
});

test('an EMPTY activities[] upsert is valid — 204, dormant snapshot (spec §4 divergence)', async () => {
  const { app, db } = makeApp();
  const res = await put(app, validBody([]));
  assert.equal(res.status, 204);
  assert.deepStrictEqual(db.rows.get(DEVICE_ID).activities, []);
});

test('a re-upsert replaces the snapshot (last-write-wins) and PRESERVES last_digest_date', async () => {
  const { app, db } = makeApp();
  await put(app, validBody());
  // Simulate the digest job having marked today between the two upserts.
  db.rows.get(DEVICE_ID).last_digest_date = new Date(2026, 7, 1); // 2026-08-01, driver shape
  const res = await put(app, validBody([ACTIVITIES[0]]));
  assert.equal(res.status, 204);
  const row = db.rows.get(DEVICE_ID);
  assert.deepStrictEqual(row.activities, [ACTIVITIES[0]], 'snapshot replaced wholesale');
  assert.deepStrictEqual(row.last_digest_date, new Date(2026, 7, 1), 'digest marker survives re-upserts');
});

// --- validation 400s (uniform { errors[] } envelope) ---
test('missing/non-hex apnsToken → 400 with path apnsToken', async () => {
  const { app } = makeApp();
  for (const bad of [undefined, '', 'not-hex!', 42]) {
    const body = validBody();
    if (bad === undefined) delete body.apnsToken; else body.apnsToken = bad;
    const res = await put(app, body);
    assert.equal(res.status, 400);
    assert.ok(res.body.errors.some((e) => e.path === 'apnsToken'));
  }
});

test('out-of-range home coords → 400 with home.lat / home.lon paths', async () => {
  const { app } = makeApp();
  const body = validBody();
  body.home = { lat: 999, lon: -999 };
  const res = await put(app, body);
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'home.lat'));
  assert.ok(res.body.errors.some((e) => e.path === 'home.lon'));
});

test('missing home → 400; non-array activities → 400', async () => {
  const { app } = makeApp();
  const noHome = validBody(); delete noHome.home;
  let res = await put(app, noHome);
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'home'));

  const badActivities = validBody(); badActivities.activities = 'nope';
  res = await put(app, badActivities);
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'activities'));
});

test('snapshot activities are validated with the SHARED rating rules (same paths/messages)', async () => {
  const { app, db } = makeApp();
  const res = await put(app, validBody([
    { id: 'bad', label: 'Bad', displayMetrics: ['temp'], thresholds: { temp: { required: true } } }, // bound-less
    { id: 'bad2', label: 'Bad2', displayMetrics: ['darkness'], thresholds: {} },                     // coming-soon
    { id: 'bad', label: 'Dup', displayMetrics: ['temp'], thresholds: {} },                            // duplicate id
  ]));
  assert.equal(res.status, 400);
  const paths = res.body.errors.map((e) => e.path);
  assert.ok(paths.includes('activities[0].thresholds.temp'));
  assert.ok(paths.includes('activities[1].displayMetrics'));
  assert.ok(paths.includes('activities[2].id'));
  assert.ok(res.body.errors.some((e) => e.message === 'a numeric threshold needs at least one of min/max'));
  assert.ok(res.body.errors.some((e) => e.message === 'coming-soon metric not yet available: darkness'));
  assert.equal(db.rows.size, 0, 'atomic: nothing stored on validation failure');
});

test('validation runs BEFORE the weather call — a bad body spends no provider call', async () => {
  let called = false;
  const spy = async () => { called = true; return DUBAI_WEATHER; };
  const { app } = makeApp({ getWeather: spy });
  await put(app, { apnsToken: '', home: {}, activities: 'x' });
  assert.equal(called, false);
});

// --- provider failure ---
test('UpstreamError resolving the timezone → 502 with the uniform envelope; nothing stored', async () => {
  const failing = async () => { throw new UpstreamError('provider down'); };
  const { app, db } = makeApp({ getWeather: failing });
  const res = await put(app, validBody());
  assert.equal(res.status, 502);
  assert.deepStrictEqual(res.body, { errors: [{ message: 'Weather data unavailable' }] });
  assert.equal(db.rows.size, 0);
});

// --- coordinate rounding at write (ADR-0010 granularity ruling) ---
test('PUT rounds home coords to 2 dp at write — for storage AND the timezone lookup; marker preserved', async () => {
  const weatherCalls = [];
  const spy = async (lat, lon) => { weatherCalls.push({ lat, lon }); return DUBAI_WEATHER; };
  const { app, db } = makeApp({ getWeather: spy });
  await put(app, validBody());
  db.rows.get(DEVICE_ID).last_digest_date = new Date(2026, 7, 1); // driver shape

  const body = validBody();
  body.home = { lat: 25.16273, lon: 55.20771 }; // full precision, as the client sends
  const res = await put(app, body);
  assert.equal(res.status, 204);
  const row = db.rows.get(DEVICE_ID);
  assert.equal(row.home_lat, 25.16, 'stored Coarse: 25.16273 → 25.16');
  assert.equal(row.home_lon, 55.21, 'stored Coarse: 55.20771 → 55.21');
  assert.deepStrictEqual(weatherCalls.at(-1), { lat: 25.16, lon: 55.21 },
    'the timezone resolution sees the SAME rounded values the row stores');
  assert.deepStrictEqual(row.last_digest_date, new Date(2026, 7, 1),
    'the rounding change does not disturb marker preservation');
});

// --- DELETE = deactivate (ADR-0010 never-erase rule) ---
test('DELETE blanks the token and KEEPS the row — activities/home/timezone/marker intact; idempotent', async () => {
  const { app, db } = makeApp();
  await put(app, validBody());
  db.rows.get(DEVICE_ID).last_digest_date = new Date(2026, 7, 1);

  let res = await supertest(app).delete(`/api/v1/devices/${DEVICE_ID}`);
  assert.equal(res.status, 204);
  const row = db.rows.get(DEVICE_ID);
  assert.ok(row, 'the row is never erased');
  assert.equal(row.apns_token, null, 'only the push address lifecycles');
  assert.deepStrictEqual(row.activities, ACTIVITIES, 'authored data survives opt-out');
  assert.equal(row.home_lat, 25.16);
  assert.equal(row.home_lon, 55.21);
  assert.equal(row.timezone, 'Asia/Dubai');
  assert.deepStrictEqual(row.last_digest_date, new Date(2026, 7, 1));

  res = await supertest(app).delete(`/api/v1/devices/${DEVICE_ID}`);
  assert.equal(res.status, 204, 'deactivating an already-deactivated row is still 204');
});

test('DELETE for an unknown deviceId is 204 and must NOT create a row', async () => {
  const { app, db } = makeApp();
  const res = await supertest(app).delete(`/api/v1/devices/${DEVICE_ID}`);
  assert.equal(res.status, 204);
  assert.equal(db.rows.size, 0, 'an UPDATE matching zero rows creates nothing');
});

test('a re-opt-in PUT after DELETE restores a token into the SAME row', async () => {
  const { app, db } = makeApp();
  await put(app, validBody());
  db.rows.get(DEVICE_ID).last_digest_date = new Date(2026, 7, 1);
  await supertest(app).delete(`/api/v1/devices/${DEVICE_ID}`);
  assert.equal(db.rows.get(DEVICE_ID).apns_token, null);

  const body = validBody();
  body.apnsToken = 'ffff0000';
  const res = await put(app, body);
  assert.equal(res.status, 204);
  assert.equal(db.rows.size, 1, 'same row — no second row on re-opt-in');
  const row = db.rows.get(DEVICE_ID);
  assert.equal(row.apns_token, 'ffff0000', 'fresh token lands in the kept row');
  assert.deepStrictEqual(row.last_digest_date, new Date(2026, 7, 1),
    'history survives the whole opt-out/re-opt-in round trip');
});
