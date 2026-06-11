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
        hourly: { data: [
          { date: '2026-06-10T00:00:00', temperature: 25, humidity: 40, wind: { speed: 10 }, precipitation: { total: 0 }, cloud_cover: { total: 10 }, visibility: 10, uv_index: 3, weather: 'clear' },
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

test('getWeather sends timezone=UTC to provider even when caller passes another zone (B4)', async (t) => {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  const getLastUrl = captureFetch();
  // Caller tries to override — should be ignored.
  await getWeather(25.16, 55.20, 'Asia/Dubai');
  const url = getLastUrl();
  assert.ok(url.includes('timezone=UTC'),     `expected timezone=UTC in URL, got: ${url}`);
  assert.ok(!url.includes('Asia%2FDubai'),    `expected Asia/Dubai NOT to leak into URL, got: ${url}`);
});

test('getWeather sends timezone=UTC by default (B4)', async (t) => {
  t.after(restore);
  process.env.API_KEY = 'test-key';
  const getLastUrl = captureFetch();
  await getWeather(25.16, 55.20);
  assert.ok(getLastUrl().includes('timezone=UTC'));
});
