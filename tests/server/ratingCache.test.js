// /rating through the shared weather cache (#6c spec §6, amended 2026-07-20).
// The existing rating tests inject a bare fake getWeather (one provider call per
// request by construction) — this file composes the router with a real
// createWeatherCache around a spy provider, so a regression that drops the
// cache from the wiring (or breaks its TTL/key behavior at the route level)
// fails here rather than passing silently.

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const { createWeatherCache } = require('../../src/services/weatherCache');
const { evaluateAll } = require('../../src/decision');
const { tagLocalDays } = require('../../src/weather/timeBoundary');

const FORECAST_START = '2026-06-19T20:00:00Z';
const TIMEZONE = 'Asia/Dubai';

function makeFixture() {
  const hours = Array.from({ length: 48 }, () => ({
    temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false,
  }));
  return { forecastStart: FORECAST_START, timezone: TIMEZONE, hours: tagLocalDays(hours, FORECAST_START, TIMEZONE) };
}

const BODY = {
  lat: 25.1627, lon: 55.2077,
  activities: [{ id: 'vb', label: 'Volleyball', displayMetrics: ['temp'],
    thresholds: { temp: { min: 15, max: 35, required: true } } }],
};

test('a repeat /rating request for a cached location within the TTL does not hit the provider twice', async () => {
  let providerCalls = 0;
  const fixture = makeFixture();
  const spyGetWeather = async () => { providerCalls++; return fixture; };
  const getWeather = createWeatherCache({ getWeather: spyGetWeather, now: () => 0 });

  const app = express();
  app.use(express.json());
  app.use('/api/v1', createRatingRouter({ getWeather, evaluateAll }));

  const first = await supertest(app).post('/api/v1/rating').send(BODY);
  const second = await supertest(app).post('/api/v1/rating').send(BODY);

  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(providerCalls, 1, 'second request must be served from the shared cache');
  // Contract unchanged through the cache — same body either way.
  assert.deepStrictEqual(second.body, first.body);
});

test('the production server wiring passes the shared cache, not the raw getWeather', () => {
  // A structural pin: src/server.js must import the weatherCache singleton.
  // (The behavioral path is covered above; this catches the wiring line being
  // reverted to createRatingRouter() with provider defaults.)
  const fs = require('node:fs');
  const path = require('node:path');
  const src = fs.readFileSync(path.join(__dirname, '../../src/server.js'), 'utf8');
  assert.match(src, /createRatingRouter\(\{\s*getWeather:\s*getCachedWeather\s*\}\)/);
});
