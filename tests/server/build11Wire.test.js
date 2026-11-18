// Build 11 keeps working: the request bodies the shipped iOS client builds
// (tests/fixtures/build11-wire/, derived from the app's encoders — uppercase
// UUID ids and device id, free-text labels, a same-day and a wrapped window,
// flag + numeric thresholds, full-precision coordinates, a 64-char lowercase
// hex push token, the dormant [] snapshot, feedback with and without `kind`)
// go through the real routers behind the default (observe) request limiter,
// with a fake provider under a real weather cache and a fake db.

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const createDevicesRouter = require('../../src/routes/devices');
const createFeedbackRouter = require('../../src/routes/feedback');
const { createWeatherCache } = require('../../src/services/weatherCache');
const { createRateLimiter } = require('../../src/middleware/rateLimit');
const { tagLocalDays } = require('../../src/weather/timeBoundary');

const rating = require('../fixtures/build11-wire/rating.json');
const snapshot = require('../fixtures/build11-wire/device-snapshot.json');
const dormant = require('../fixtures/build11-wire/device-snapshot-dormant.json');
const feedbackWithKind = require('../fixtures/build11-wire/feedback-with-kind.json');
const feedbackWithoutKind = require('../fixtures/build11-wire/feedback-without-kind.json');

const FORECAST_START = '2026-06-19T20:00:00Z'; // 00:00 in Asia/Dubai
const TIMEZONE = 'Asia/Dubai';

function makeForecast() {
  const hours = Array.from({ length: 72 }, () => ({
    temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: ['full moon'], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false,
  }));
  return { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: tagLocalDays(hours, FORECAST_START, TIMEZONE) };
}

function makeFakeDb() {
  const queries = [];
  return {
    queries,
    query: async (text, params) => {
      queries.push({ text, params });
      return { rows: [], rowCount: 1 };
    },
  };
}

function makeApp() {
  const providerCalls = [];
  const forecast = makeForecast();
  const cache = createWeatherCache({
    getWeather: async (lat, lon) => { providerCalls.push([lat, lon]); return forecast; },
    log: () => {},
  });
  const db = makeFakeDb();
  const app = express();
  app.set('trust proxy', 1);
  app.use('/api/v1', createRateLimiter({ name: 'api-minute', limit: 120, windowMs: 60_000, log: () => {} }));
  app.use(express.json());
  app.use('/api/v1', createRatingRouter({ getWeather: cache }));
  app.use('/api/v1', createDevicesRouter({ getWeather: cache, db }));
  app.use('/api/v1', createFeedbackRouter({ db }));
  return { app, db, providerCalls };
}

test('fixture shapes match what the iOS encoders produce', () => {
  const UPPER_UUID = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;
  for (const a of rating.activities) {
    assert.match(a.id, UPPER_UUID);
    assert.ok(a.window, 'live activities always carry a window (dormant ones are not sent)');
  }
  assert.ok(rating.activities.some((a) => a.window.startHour < a.window.endHour), 'a same-day window');
  assert.ok(rating.activities.some((a) => a.window.startHour > a.window.endHour), 'a wrapped window');
  assert.ok(rating.activities.some((a) => Object.values(a.thresholds).some((t) => t.type === 'flag')));
  assert.notEqual(Math.round(rating.lat * 100) / 100, rating.lat, 'full-precision coordinates');
  assert.match(snapshot.deviceId, UPPER_UUID);
  assert.match(snapshot.body.apnsToken, /^[0-9a-f]{64}$/);
  assert.equal(snapshot.body.activities.length, 2);
  assert.deepStrictEqual(dormant.body.activities, []);
  assert.equal(feedbackWithKind.kind, 'liked');
  assert.equal('kind' in feedbackWithoutKind, false);
});

test('build 11 /rating body → 200, every activity echoed', async () => {
  const { app, providerCalls } = makeApp();
  const res = await supertest(app).post('/api/v1/rating').send(rating);
  assert.equal(res.status, 200);
  assert.deepStrictEqual(res.body.activities.map((a) => a.activityId), rating.activities.map((a) => a.id));
  assert.deepStrictEqual(providerCalls, [[25.2, 55.27]]);
});

test('build 11 device snapshot (uppercase device id, two activities) → 204', async () => {
  const { app, db, providerCalls } = makeApp();
  const res = await supertest(app).put(`/api/v1/devices/${snapshot.deviceId}`).send(snapshot.body);
  assert.equal(res.status, 204);
  assert.equal(db.queries.length, 1);
  assert.equal(db.queries[0].params[0], snapshot.deviceId);
  assert.equal(providerCalls.length, 1, 'the timezone lookup went through the cache');
});

test('build 11 dormant snapshot (activities: []) → 204', async () => {
  const { app } = makeApp();
  const res = await supertest(app).put(`/api/v1/devices/${dormant.deviceId}`).send(dormant.body);
  assert.equal(res.status, 204);
});

test('build 11 opt-out (DELETE) → 204', async () => {
  const { app } = makeApp();
  const res = await supertest(app).delete(`/api/v1/devices/${snapshot.deviceId}`);
  assert.equal(res.status, 204);
});

test('build 11 feedback with kind → 204', async () => {
  const { app, db } = makeApp();
  const res = await supertest(app).post('/api/v1/feedback').send(feedbackWithKind);
  assert.equal(res.status, 204);
  assert.equal(db.queries[0].params[5], 'liked');
});

test('feedback without kind (older builds) → 204, stored as suggestion', async () => {
  const { app, db } = makeApp();
  const res = await supertest(app).post('/api/v1/feedback').send(feedbackWithoutKind);
  assert.equal(res.status, 204);
  assert.equal(db.queries[0].params[5], 'suggestion');
});
