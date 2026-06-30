const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const realApp = require('../../src/server'); // production wiring — has the body-parser error handler
const { UpstreamError } = require('../../src/weather/UpstreamError');
const { tagLocalDays } = require('../../src/weather/timeBoundary');

// forecastStart 20:00Z = 00:00 Asia/Dubai (+4), so index 0 sits on a local
// midnight and the horizon splits into clean full calendar days:
//   day 0 = 2026-06-20 (indices 0-23), day 1 = 2026-06-21 (indices 24-47).
// Clean 24/24 keeps every expected window index hand-verifiable.
const FORECAST_START = '2026-06-19T20:00:00Z';
const TIMEZONE = 'Asia/Dubai';

// What getWeather returns: tagged hours (internal localDay/localHour, no `hour`) —
// the route strips the internal tags and prepends index for the wire.
function makeTaggedHours(count = 48, overrides = {}) {
  const hours = Array.from({ length: count }, () => ({
    temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false, ...overrides,
  }));
  return tagLocalDays(hours, FORECAST_START, TIMEZONE);
}

function makeApp({ getWeather, evaluateAll }) {
  const app = express();
  app.use(express.json());
  app.use('/api/v1', createRatingRouter({ getWeather, evaluateAll }));
  return app;
}

// Caller-supplied activities (ADR-0005). All metrics are LIVE so the body is valid.
const REQUEST_ACTIVITIES = [
  { id: 'boat-fishing-pro', label: 'Boat Fishing Pro', displayMetrics: ['temp'],
    thresholds: { temp: { min: 15, max: 35, required: true } } },
  { id: 'volleyball', label: 'Volleyball', displayMetrics: ['temp', 'windSpeed'],
    thresholds: { temp: { min: 15, max: 35, required: true }, windSpeed: { max: 15, required: false } } },
];
function validBody(activities = REQUEST_ACTIVITIES) {
  return { lat: 25.1627, lon: 55.2077, activities };
}

const happyFixture = { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: makeTaggedHours() };
const happyGetWeather = async () => happyFixture;
const realEvaluateAll = require('../../src/decision').evaluateAll;

const post = (app, body) => supertest(app).post('/api/v1/rating').send(body);

// --- validation 400s (ADR-0005, uniform { errors: [...] }) ---
test('missing lat returns 400 with a structured errors[] body', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const body = validBody(); delete body.lat;
  const res = await post(app, body);
  assert.equal(res.status, 400);
  assert.ok(Array.isArray(res.body.errors));
  assert.ok(res.body.errors.some((e) => e.path === 'lat'));
});

test('an invalid activity rejects the whole request atomically (400)', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const body = validBody([
    REQUEST_ACTIVITIES[0],
    { id: 'bad', label: 'Bad', displayMetrics: ['temp'], thresholds: { temp: { required: true } } }, // bound-less
  ]);
  const res = await post(app, body);
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.length > 0);
});

test('validation runs BEFORE getWeather — a bad body spends no provider call', async () => {
  let called = false;
  const spyGetWeather = async () => { called = true; return happyFixture; };
  const app = makeApp({ getWeather: spyGetWeather, evaluateAll: realEvaluateAll });
  await post(app, { lat: 999, lon: 0, activities: [] });
  assert.equal(called, false);
});

// --- happy path ---
test('valid POST returns 200 with the day-bucketed top-level shape', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.equal(res.status, 200);
  assert.ok('forecastStart' in res.body);
  assert.equal(res.body.timezone, 'Asia/Dubai');
  assert.ok(Array.isArray(res.body.activities));
  assert.ok(Array.isArray(res.body.hours));
});

test('hours are dense with contiguous index and no internal tag leak', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.equal(res.body.hours.length, 48);
  res.body.hours.forEach((h, i) => {
    assert.equal(h.index, i);
    assert.equal('localDay' in h, false, 'internal localDay must not reach the wire');
    assert.equal('localHour' in h, false, 'internal localHour must not reach the wire');
    assert.equal('hour' in h, false, 'UTC hour is dropped (ADR-0004b)');
  });
});

test('response activities echo the caller-supplied activities, in order', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.deepStrictEqual(res.body.activities.map((a) => a.activityId), ['boat-fishing-pro', 'volleyball']);
  for (const a of res.body.activities) {
    assert.ok(Array.isArray(a.days));
    assert.equal('rating' in a, false);
    a.days.forEach((d, i) => assert.equal(d.dayIndex, i));
  }
});

// --- error envelope: uniform across 502/500 (ADR-0005 §6) ---
test('UpstreamError from getWeather → 502 with errors[] envelope', async () => {
  const failingGetWeather = async () => { throw new UpstreamError('provider down'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.equal(res.status, 502);
  assert.ok(Array.isArray(res.body.errors));
  assert.equal(res.body.errors.length, 1);
  assert.equal(res.body.errors[0].message, 'Weather data unavailable');
});

test('generic Error from getWeather → 500 with errors[] envelope, not 502', async () => {
  const failingGetWeather = async () => { throw new Error('fetch is not defined'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.equal(res.status, 500);
  assert.ok(Array.isArray(res.body.errors));
  assert.equal(res.body.errors.length, 1);
});

// --- body-parser failures use the SAME envelope (ADR-0005 §6) ---
// These run against the real src/server.js: express.json() throws before the route,
// so getWeather is never reached and the production middleware is what's under test.
test('malformed JSON body → 400 with the uniform { errors[] } envelope, not HTML', async () => {
  const res = await supertest(realApp)
    .post('/api/v1/rating')
    .set('Content-Type', 'application/json')
    .send('{ not valid json');
  assert.equal(res.status, 400);
  assert.match(res.headers['content-type'], /application\/json/);
  assert.ok(Array.isArray(res.body.errors));
  assert.equal(res.body.errors.length, 1);
});

test('oversized body (>100kb) → 413 with the uniform { errors[] } envelope', async () => {
  const huge = JSON.stringify({ lat: 25, lon: 55, activities: [], pad: 'x'.repeat(200 * 1024) });
  const res = await supertest(realApp)
    .post('/api/v1/rating')
    .set('Content-Type', 'application/json')
    .send(huge);
  assert.equal(res.status, 413);
  assert.match(res.headers['content-type'], /application\/json/);
  assert.ok(Array.isArray(res.body.errors));
  assert.equal(res.body.errors.length, 1);
});

// --- no timezone in request (ADR-0005): getWeather called with exactly (lat, lon) ---
test('a stray timezone field in the body is ignored — getWeather gets (lat, lon) only', async () => {
  let receivedArgs = null;
  const spyGetWeather = async (...args) => { receivedArgs = args; return happyFixture; };
  const app = makeApp({ getWeather: spyGetWeather, evaluateAll: realEvaluateAll });
  const body = validBody(); body.timezone = 'Asia/Dubai';
  const res = await post(app, body);
  assert.equal(res.status, 200);
  assert.equal(receivedArgs.length, 2, `expected only (lat, lon), got ${receivedArgs.length}`);
});

// --- null-day wire convention ---
test('a null-rated day keeps its slot with the window fields absent (ADR-0004 sub-decision 3)', async () => {
  const fixture = { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: makeTaggedHours(48, { temp: 100 }) };
  const app = makeApp({ getWeather: async () => fixture, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  const allDays = res.body.activities.flatMap((a) => a.days);
  const nullDays = allDays.filter((d) => d.rating === null);
  assert.ok(nullDays.length > 0);
  for (const d of nullDays) {
    assert.deepStrictEqual(Object.keys(d), ['dayIndex', 'rating']);
  }
});

// --- partial day-0 + non-uniform offset ---
test('partial day-0: variable-length buckets with a non-24 global offset (ADR-0003)', async () => {
  const partialHours = (() => {
    const hours = Array.from({ length: 37 }, () => ({
      temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
      cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
      darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
      tide: 0, seaWarning: false,
    }));
    return tagLocalDays(hours, '2026-06-22T07:00:00Z', TIMEZONE);
  })();
  const fixture = { forecastStart: '2026-06-22T07:00:00Z', timezone: TIMEZONE, hours: partialHours };
  const app = makeApp({ getWeather: async () => fixture, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());

  assert.equal(res.body.hours.length, 37);
  const vb = res.body.activities.find((a) => a.activityId === 'volleyball');
  assert.equal(vb.days.length, 2);
  vb.days.forEach((d, i) => assert.equal(d.dayIndex, i));
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 0,  endIndex: 13, duration: 13 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 13, endIndex: 37, duration: 24 });
});

// --- night-stitch at the wire: per-activity days.length, dayIndex contiguous (ADR-0004 amendment) ---
test('a nocturnal (wrapped-window) activity buckets by night; days.length is per-activity', async () => {
  // 16:00 local start, 60h horizon -> diurnal 4 calendar days, nocturnal 3 nights.
  const hours = (() => {
    const raw = Array.from({ length: 60 }, () => ({
      temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
      cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
      darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
      tide: 0, seaWarning: false,
    }));
    return tagLocalDays(raw, '2026-06-19T12:00:00Z', TIMEZONE);
  })();
  const app = makeApp({ getWeather: async () => ({ forecastStart: '2026-06-19T12:00:00Z', timezone: TIMEZONE, hours }), evaluateAll: realEvaluateAll });

  const body = validBody([
    { id: 'walk', label: 'Walk', displayMetrics: ['temp'], thresholds: { temp: { min: 15, max: 35, required: true } } },
    { id: 'star', label: 'Stargazing', displayMetrics: ['temp', 'cloudCover'],
      thresholds: { temp: { min: 5, max: 35, required: true }, cloudCover: { max: 30, required: true } },
      window: { startHour: 22, endHour: 2 } },
  ]);
  const res = await post(app, body);
  assert.equal(res.status, 200);

  const walk = res.body.activities.find((a) => a.activityId === 'walk');
  const star = res.body.activities.find((a) => a.activityId === 'star');
  assert.equal(walk.days.length, 4, 'diurnal: 4 calendar days');
  assert.equal(star.days.length, 3, 'nocturnal: 3 nights (per-activity days.length)');
  star.days.forEach((d, i) => assert.equal(d.dayIndex, i)); // dense from 0 within the activity
  // night 2 spans the local midnight: day2 22:00,23:00 (idx 54,55) + day3 00:00,01:00 (idx 56,57)
  assert.deepStrictEqual(star.days[2], { dayIndex: 2, rating: 'perfect', startIndex: 54, endIndex: 58, duration: 4 });
});

// --- golden snapshot — the executable spec (hand-verified against ADR-0004/0005) ---
test('golden: full response shape, key order, and global window indices', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await post(app, validBody());
  assert.equal(res.status, 200);

  // Top-level key order (ADR-0004): forecastStart, timezone, activities, hours
  assert.deepStrictEqual(Object.keys(res.body), ['forecastStart', 'timezone', 'activities', 'hours']);
  assert.equal(res.body.forecastStart, '2026-06-19T20:00:00Z');
  assert.equal(res.body.timezone, 'Asia/Dubai');

  // activities[] echo the request order
  assert.deepStrictEqual(res.body.activities.map((a) => a.activityId), ['boat-fishing-pro', 'volleyball']);

  // Per-activity key order: activityId, label, displayMetrics, days
  for (const a of res.body.activities) {
    assert.deepStrictEqual(Object.keys(a), ['activityId', 'label', 'displayMetrics', 'days']);
    assert.equal(a.days.length, 2);
  }

  // Per-day key order + GLOBAL indices; day 1's offset (24/48) is the silent-offset tripwire.
  const vb = res.body.activities.find((a) => a.activityId === 'volleyball');
  assert.deepStrictEqual(Object.keys(vb.days[0]), ['dayIndex', 'rating', 'startIndex', 'endIndex', 'duration']);
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 0,  endIndex: 24, duration: 24 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 24, endIndex: 48, duration: 24 });

  // hours[] — per-hour wire key order: index first, `hour` dropped, internal tags stripped
  assert.equal(res.body.hours.length, 48);
  assert.deepStrictEqual(Object.keys(res.body.hours[0]), [
    'index', 'temp', 'humidity', 'windSpeed', 'rainFall', 'cloudCover',
    'visibility', 'moon', 'uV', 'dustAlert',
    'darkness', 'douglasScale', 'swellHeight', 'swellLength', 'tide', 'seaWarning',
  ]);
});
