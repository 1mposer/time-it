const test = require('node:test');
const assert = require('node:assert/strict');

const { createWeatherCache, TTL_MS } = require('../../src/services/weatherCache');

const FIXTURE = { forecastStart: '2026-08-01T02:00:00Z', timezone: 'Asia/Dubai', hours: [] };

function makeSpyGetWeather(result = FIXTURE) {
  const calls = [];
  const fn = async (lat, lon) => { calls.push([lat, lon]); return result; };
  return { fn, calls };
}

test('a second call for the same location within the TTL does not hit the provider', async () => {
  const { fn, calls } = makeSpyGetWeather();
  const cached = createWeatherCache({ getWeather: fn, now: () => 0 });
  const a = await cached(25.1627, 55.2077);
  const b = await cached(25.1627, 55.2077);
  assert.equal(calls.length, 1);
  assert.equal(a, b);
});

test('coords that round to the same 2 dp key share one entry (~1.1 km grid)', async () => {
  const { fn, calls } = makeSpyGetWeather();
  const cached = createWeatherCache({ getWeather: fn, now: () => 0 });
  await cached(25.1627, 55.2077);
  await cached(25.1632, 55.2081); // both round to 25.16,55.21
  assert.equal(calls.length, 1);
});

test('coords that differ at 2 dp are separate entries', async () => {
  const { fn, calls } = makeSpyGetWeather();
  const cached = createWeatherCache({ getWeather: fn, now: () => 0 });
  await cached(25.16, 55.21);
  await cached(25.17, 55.21);
  assert.equal(calls.length, 2);
});

test('an entry older than the TTL is refetched; a fresh one is not', async () => {
  const { fn, calls } = makeSpyGetWeather();
  let clock = 0;
  const cached = createWeatherCache({ getWeather: fn, now: () => clock });
  await cached(25.16, 55.21);
  clock = TTL_MS - 1;
  await cached(25.16, 55.21);
  assert.equal(calls.length, 1, 'still inside the TTL — served from cache');
  clock = TTL_MS;
  await cached(25.16, 55.21);
  assert.equal(calls.length, 2, 'TTL elapsed — refetched');
});

test('concurrent calls for the same key share one in-flight provider call', async () => {
  let resolveFetch;
  let callCount = 0;
  const getWeather = () => { callCount++; return new Promise((resolve) => { resolveFetch = resolve; }); };
  const cached = createWeatherCache({ getWeather, now: () => 0 });
  const p1 = cached(25.16, 55.21);
  const p2 = cached(25.16, 55.21);
  resolveFetch(FIXTURE);
  assert.equal(await p1, FIXTURE);
  assert.equal(await p2, FIXTURE);
  assert.equal(callCount, 1);
});

test('a rejected fetch is not cached — the next call retries the provider', async () => {
  let fail = true;
  const calls = [];
  const getWeather = async (lat, lon) => {
    calls.push([lat, lon]);
    if (fail) throw new Error('provider down');
    return FIXTURE;
  };
  const cached = createWeatherCache({ getWeather, now: () => 0 });
  await assert.rejects(() => cached(25.16, 55.21), /provider down/);
  fail = false;
  const result = await cached(25.16, 55.21);
  assert.equal(result, FIXTURE);
  assert.equal(calls.length, 2, 'the failure was evicted, so the second call refetched');
});
