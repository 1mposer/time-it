// The production job wiring: both scheduled jobs must read weather through the
// shared cache as origin 'job' — uncounted by the outside provider budget and
// never served a stale forecast. The cache's default origin is 'outside', so a
// missing wrapper would let outside traffic starve the jobs without failing
// anything else; these tests pin it.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { startJobs, jobWeather } = require('../../src/jobs');
const { createWeatherCache, TTL_MS } = require('../../src/services/weatherCache');
const { UpstreamError } = require('../../src/weather/UpstreamError');

function captureJobDeps(cache) {
  const received = {};
  const scheduled = [];
  startJobs({
    schedule: (expr, fn) => scheduled.push({ expr, fn }),
    weatherCache: cache,
    jobFactories: {
      createDailyDigestJob: (deps) => { received.digest = deps; return { runDigestPass: async () => {} }; },
      createPerfectWindowDetectorJob: (deps) => { received.detector = deps; return { runDetectorPass: async () => {} }; },
    },
  });
  return { received, scheduled };
}

test('both jobs get a weather function that calls the cache with origin job', async () => {
  const calls = [];
  const spyCache = async (...args) => { calls.push(args); return { ok: true }; };
  const { received, scheduled } = captureJobDeps(spyCache);

  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].expr, '0 * * * *');

  await received.digest.getWeather(25.16, 55.21);
  await received.detector.getWeather(43.65, -79.38);
  assert.deepStrictEqual(calls, [
    [25.16, 55.21, { origin: 'job' }],
    [43.65, -79.38, { origin: 'job' }],
  ]);
});

test('the job weather function never asks for stale data, whatever it is passed', async () => {
  const calls = [];
  const wrapped = jobWeather(async (...args) => { calls.push(args); });
  await wrapped(1, 2, { allowStale: true, origin: 'outside', clientKey: '203.0.113.7' });
  assert.deepStrictEqual(calls, [[1, 2, { origin: 'job' }]]);
});

test('through a real cache, a job read rejects when the provider is down — no stale forecast', async () => {
  let clock = Date.parse('2026-08-01T02:00:00Z');
  let fail = false;
  const forecast = { forecastStart: '2026-08-01T02:00:00Z', timezone: 'Asia/Dubai', hours: [] };
  const cache = createWeatherCache({
    getWeather: async () => { if (fail) throw new UpstreamError('provider down'); return forecast; },
    now: () => clock,
    outsideBudgetPerHour: 0,
    log: () => {},
  });
  const { received } = captureJobDeps(cache);

  assert.equal(await received.detector.getWeather(25.16, 55.21), forecast,
    'a job fetches even with an outside budget of zero');
  fail = true;
  clock += TTL_MS;
  await assert.rejects(() => received.digest.getWeather(25.16, 55.21), UpstreamError);
});

test('the production wiring defaults to the shared cache singleton', () => {
  const src = fs.readFileSync(path.join(__dirname, '../../src/jobs/index.js'), 'utf8');
  assert.match(src, /weatherCache\s*=\s*getCachedWeather/);
  assert.match(src, /getWeather:\s*jobWeather\(weatherCache\)/);
});
