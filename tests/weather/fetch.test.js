const test = require('node:test');
const assert = require('node:assert/strict');
const { fetchWeather } = require('../../src/weather/fetch');
const { UpstreamError } = require('../../src/weather/UpstreamError');

const originalFetch = global.fetch;

function restoreFetch() {
  global.fetch = originalFetch;
}

test('fetchWeather returns parsed JSON on a 200 response', async (t) => {
  t.after(restoreFetch);
  global.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => ({ hourly: { data: [] } }),
  });
  const raw = await fetchWeather({ lat: 0, lon: 0 });
  assert.deepEqual(raw, { hourly: { data: [] } });
});

test('fetchWeather throws UpstreamError on non-ok HTTP response (B3)', async (t) => {
  t.after(restoreFetch);
  global.fetch = async () => ({
    ok: false,
    status: 503,
    json: async () => ({}),
  });
  await assert.rejects(
    () => fetchWeather({ lat: 0, lon: 0 }),
    UpstreamError,
  );
});

test('fetchWeather wraps network errors in UpstreamError (B3)', async (t) => {
  t.after(restoreFetch);
  global.fetch = async () => {
    const err = new Error('getaddrinfo ENOTFOUND meteosource.com');
    err.code = 'ENOTFOUND';
    throw err;
  };
  await assert.rejects(
    () => fetchWeather({ lat: 0, lon: 0 }),
    UpstreamError,
  );
});

test('fetchWeather wraps timeout errors in UpstreamError (B3)', async (t) => {
  t.after(restoreFetch);
  global.fetch = async () => {
    const err = new Error('connect ETIMEDOUT');
    err.code = 'ETIMEDOUT';
    throw err;
  };
  await assert.rejects(
    () => fetchWeather({ lat: 0, lon: 0 }),
    UpstreamError,
  );
});
