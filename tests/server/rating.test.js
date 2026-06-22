const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const { UpstreamError } = require('../../src/weather/UpstreamError');
const { tagLocalDays } = require('../../src/weather/timeBoundary');

// forecastStart 20:00Z = 00:00 Asia/Dubai (+4), so index 0 sits on a local
// midnight and the horizon splits into clean full calendar days:
//   day 0 = 2026-06-20 (indices 0-23), day 1 = 2026-06-21 (indices 24-47).
// Clean 24/24 keeps every expected window index hand-verifiable.
const FORECAST_START = '2026-06-19T20:00:00Z';
const TIMEZONE = 'Asia/Dubai';

// What getWeather returns: tagged hours (internal localDay, no `hour`) — the
// route strips localDay and prepends index for the wire.
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

const happyFixture = { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: makeTaggedHours() };
const happyGetWeather = async () => happyFixture;
const realEvaluateAll = require('../../src/decision').evaluateAll;

test('missing lat returns 400', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lon=55.2077');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lat');
});

test('missing lon returns 400', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lon');
});

test('valid request returns 200 with the day-bucketed top-level shape', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 200);
  assert.ok('forecastStart' in res.body);
  assert.equal(res.body.timezone, 'Asia/Dubai');
  assert.ok(Array.isArray(res.body.activities));
  assert.ok(Array.isArray(res.body.hours));
});

test('hours are dense with contiguous index and no internal localDay leak', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.body.hours.length, 48);
  res.body.hours.forEach((h, i) => {
    assert.equal(h.index, i);
    assert.equal('localDay' in h, false, 'internal localDay must not reach the wire');
    assert.equal('hour' in h, false, 'UTC hour is dropped (ADR-0004b)');
  });
});

test('each activity carries days[] (no top-level singular rating/window)', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  for (const activity of res.body.activities) {
    assert.ok('activityId' in activity);
    assert.ok('label' in activity);
    assert.ok('displayMetrics' in activity);
    assert.ok(Array.isArray(activity.days), `missing days[] on ${activity.activityId}`);
    assert.equal('rating' in activity, false, `top-level rating must be gone on ${activity.activityId}`);
    // dense, contiguous dayIndex — read THIS activity's own length, never a magic 7
    activity.days.forEach((d, i) => assert.equal(d.dayIndex, i));
  }
});

// B3 — provider failures surface as 502
test('UpstreamError from getWeather → 502 (B3)', async () => {
  const failingGetWeather = async () => { throw new UpstreamError('provider down'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 502);
  assert.equal(res.body.error, 'Weather data unavailable');
});

// B3 — internal/unexpected errors surface as 500, NOT 502
test('Generic Error from getWeather → 500, not 502 (B3)', async () => {
  const failingGetWeather = async () => { throw new Error('fetch is not defined'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 500);
});

// B4 — timezone query param is ignored: getWeather is never called with a third arg
test('timezone query param is ignored — not forwarded to getWeather (B4)', async () => {
  let receivedArgs = null;
  const spyGetWeather = async (...args) => { receivedArgs = args; return happyFixture; };
  const app = makeApp({ getWeather: spyGetWeather, evaluateAll: realEvaluateAll });
  await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077&timezone=Asia/Dubai');
  assert.equal(receivedArgs.length, 2, `expected only (lat, lon), got ${receivedArgs.length}`);
});

// Null-day wire convention: object present, rating null, window triplet absent.
test('a null-rated day keeps its slot with the window fields absent (ADR-0004 sub-decision 3)', async () => {
  // Extreme temp fails every activity's required temp threshold on every day.
  const fixture = { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: makeTaggedHours(48, { temp: 100 }) };
  const app = makeApp({ getWeather: async () => fixture, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');

  const allDays = res.body.activities.flatMap(a => a.days);
  const nullDays = allDays.filter(d => d.rating === null);
  assert.ok(nullDays.length > 0);
  for (const d of nullDays) {
    assert.deepStrictEqual(Object.keys(d), ['dayIndex', 'rating'], 'null day must carry only dayIndex + rating');
  }
});

// Partial day-0 + non-uniform offset. forecastStart 07:00Z = 11:00 Asia/Dubai,
// so day 0 is a PARTIAL 13-hour bucket (indices 0-12) and day 1 a full 24 hours
// (indices 13-36). This is the asymmetric case the clean midnight fixture can't
// reach: it pins partial-day bucketing AND a non-24 global offset on day 1.
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
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');

  assert.equal(res.body.hours.length, 37);
  const vb = res.body.activities.find(a => a.activityId === 'volleyball');
  // Read this activity's own days.length — never a magic 7.
  assert.equal(vb.days.length, 2);
  vb.days.forEach((d, i) => assert.equal(d.dayIndex, i));
  // day 0 is the 13-hour partial; day 1's window starts at global index 13, not 24.
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 0,  endIndex: 13, duration: 13 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 13, endIndex: 37, duration: 24 });
});

// Golden snapshot — the executable spec. assert.deepStrictEqual ignores key order,
// so Object.keys() is asserted separately. Hand-verified against ADR-0004; any
// silent drift in field name, type, order, or the global-index offset breaks here.
test('golden: full response shape, key order, and global window indices match ADR-0004', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 200);

  // Top-level key order gains `timezone` (ADR-0004): forecastStart, timezone, activities, hours
  assert.deepStrictEqual(Object.keys(res.body), ['forecastStart', 'timezone', 'activities', 'hours']);
  assert.equal(res.body.forecastStart, '2026-06-19T20:00:00Z');
  assert.equal(res.body.timezone, 'Asia/Dubai');

  // activities[] — canonical dashboard order
  assert.deepStrictEqual(
    res.body.activities.map(a => a.activityId),
    ['boat-fishing-pro', 'boat-fishing-lite', 'shore-fishing', 'volleyball', 'stargazing-lite'],
  );

  // Per-activity key order: activityId, label, displayMetrics, days (no singular window)
  for (const a of res.body.activities) {
    assert.deepStrictEqual(Object.keys(a), ['activityId', 'label', 'displayMetrics', 'days'],
      `unexpected key order on ${a.activityId}`);
    // Read this activity's own days.length (per-activity contract); fixture buckets into 2.
    assert.equal(a.days.length, 2, `${a.activityId} should bucket into 2 local days`);
  }

  // Per-day key order + GLOBAL indices. Happy fixture is all-perfect, so each day
  // is a full-day window; day 1's offset (24/48) is the silent-offset tripwire.
  const vb = res.body.activities.find(a => a.activityId === 'volleyball');
  assert.deepStrictEqual(Object.keys(vb.days[0]), ['dayIndex', 'rating', 'startIndex', 'endIndex', 'duration']);
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 0,  endIndex: 24, duration: 24 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 24, endIndex: 48, duration: 24 });

  // hours[] — per-hour wire key order: index first, `hour` dropped, localDay stripped
  assert.equal(res.body.hours.length, 48);
  assert.deepStrictEqual(Object.keys(res.body.hours[0]), [
    'index', 'temp', 'humidity', 'windSpeed', 'rainFall', 'cloudCover',
    'visibility', 'moon', 'uV', 'dustAlert',
    'darkness', 'douglasScale', 'swellHeight', 'swellLength', 'tide', 'seaWarning',
  ]);
});
