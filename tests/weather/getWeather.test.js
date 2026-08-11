const test = require('node:test');
const assert = require('node:assert/strict');
const { getWeather } = require('../../src/weather');

const originalFetch = global.fetch;
const originalApiKey = process.env.API_KEY;

function captureFetch() {
  let lastUrl = null;
  global.fetch = async (url) => {
    lastUrl = url;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        timezone: 'Asia/Dubai',
        hourly: { data: [
          { date: '2026-06-10T00:00:00', temperature: 25, humidity: 40, wind: { speed: 10 }, precipitation: { total: 0 }, cloud_cover: { total: 10 }, visibility: 10, uv_index: 3, weather: 'clear' },
          { date: '2026-06-10T01:00:00', temperature: 25, humidity: 40, wind: { speed: 10 }, precipitation: { total: 0 }, cloud_cover: { total: 10 }, visibility: 10, uv_index: 3, weather: 'clear' },
        ] },
        astro:  { data: [{ moon_phase: 'waxing crescent' }] },
      }),
    };
  };
  return () => lastUrl;
}

function restore() {
  global.fetch = originalFetch;
  if (originalApiKey === undefined) delete process.env.API_KEY;
  else process.env.API_KEY = originalApiKey;
}

test('getWeather throws a clear error containing "API_KEY" when env var is unset (B1)', async (t) => {
  t.after(restore);
  delete process.env.API_KEY;
  // Poisoned fetch — if the guard exists, fetch is never invoked; if it doesn't,
  // this generic error surfaces and the assertion below fails (the message lacks "API_KEY").
  global.fetch = async () => { throw new Error('poisoned-fetch'); };
  await assert.rejects(
    () => getWeather(25.16, 55.20),
    (err) => err.message.includes('API_KEY'),
  );
});

test('getWeather requests timezone=auto so the provider exposes the location zone (ADR-0003)', async (t) => {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  const getLastUrl = captureFetch();
  await getWeather(25.16, 55.20);
  const url = getLastUrl();
  assert.ok(url.includes('timezone=auto'), `expected timezone=auto in URL, got: ${url}`);
  assert.ok(!url.includes('timezone=UTC'), `timezone=UTC must not be sent, got: ${url}`);
});

test('getWeather targets the standard 7-day endpoint, not /free/ (ADR-0003)', async (t) => {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  const getLastUrl = captureFetch();
  await getWeather(25.16, 55.20);
  const url = getLastUrl();
  assert.ok(url.includes('/standard/point'), `expected /standard/point endpoint, got: ${url}`);
  assert.ok(!url.includes('/free/point'), `must not hit /free/point (caps at 24h), got: ${url}`);
});

test('getWeather surfaces the location timezone and tags each hour with an internal localDay', async (t) => {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  captureFetch();
  const { forecastStart, timezone, hours } = await getWeather(25.16, 55.20);
  assert.equal(timezone, 'Asia/Dubai');
  // 00:00 Asia/Dubai = 2026-06-09T20:00:00Z; forecastStart is UTC-Z.
  assert.equal(forecastStart, '2026-06-09T20:00:00Z');
  // localDay is the forecast-location calendar day (internal — stripped at the wire).
  assert.equal(hours[0].localDay, '2026-06-10');
});
