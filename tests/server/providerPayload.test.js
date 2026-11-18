// Malformed provider payloads through the real route and the real weather
// module (only global fetch is faked): a provider fault must reach the client
// as the transient 502, never as a 500 "server defect".

const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const { getWeather } = require('../../src/weather');

const originalFetch = global.fetch;
const originalApiKey = process.env.API_KEY;
function restore() {
  global.fetch = originalFetch;
  if (originalApiKey === undefined) delete process.env.API_KEY;
  else process.env.API_KEY = originalApiKey;
}

function makeApp() {
  const app = express();
  app.use(express.json());
  app.use('/api/v1', createRatingRouter({ getWeather }));
  return app;
}

const BODY = {
  lat: 25.1627, lon: 55.2077,
  activities: [{ id: 'vb', label: 'Volleyball', displayMetrics: ['temp'],
    thresholds: { temp: { min: 15, max: 35, required: true } } }],
};

const HOUR = { date: '2026-06-10T00:00:00', temperature: 25, humidity: 40, wind: { speed: 10 },
  precipitation: { total: 0 }, cloud_cover: { total: 10 }, visibility: 10, uv_index: 3 };

async function expect502(t, fakeFetch) {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  global.fetch = fakeFetch;
  const res = await supertest(makeApp()).post('/api/v1/rating').send(BODY);
  assert.equal(res.status, 502);
  assert.deepStrictEqual(res.body, { errors: [{ message: 'Weather data unavailable' }] });
}

test('a non-JSON provider body maps to 502 not 500', async (t) => {
  await expect502(t, async () => ({
    ok: true, status: 200,
    json: async () => { throw new SyntaxError('Unexpected token < in JSON'); },
  }));
});

test('a provider payload with no timezone is a 502', async (t) => {
  await expect502(t, async () => ({
    ok: true, status: 200,
    json: async () => ({ hourly: { data: [HOUR] }, daily: { data: [] } }),
  }));
});

test('a provider payload with no hourly section is a 502', async (t) => {
  await expect502(t, async () => ({
    ok: true, status: 200,
    json: async () => ({ timezone: 'Asia/Dubai', daily: { data: [] } }),
  }));
});
