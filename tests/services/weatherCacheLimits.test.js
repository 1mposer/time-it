// The weather cache's provider-call limits, negative cache, stale serving and
// size cap. Every test drives a fake provider and a fake clock through the
// createWeatherCache factory — no network, no timers.

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createWeatherCache, NEGATIVE_TTL_MS, STALE_MAX_MS, TTL_MS,
} = require('../../src/services/weatherCache');
const { UpstreamError } = require('../../src/weather/UpstreamError');

const HOUR = 60 * 60 * 1000;
const MINUTE = 60 * 1000;

// forecastStart 02:00Z = 06:00 in Asia/Dubai (+4), so up to 18 h later is
// still the same location-local day.
const MORNING = Date.parse('2026-08-01T02:00:00Z');
const morningForecast = { forecastStart: '2026-08-01T02:00:00Z', timezone: 'Asia/Dubai', hours: [] };

// A controllable provider: records calls; `mode` = 'ok' | 'fail' | 'hang'.
function makeProvider(value = morningForecast) {
  const provider = {
    calls: [],
    mode: 'ok',
    pending: [],
    fn: async (lat, lon) => {
      provider.calls.push([lat, lon]);
      if (provider.mode === 'fail') throw new UpstreamError('provider down');
      if (provider.mode === 'hang') {
        return new Promise((resolve, reject) => provider.pending.push({ resolve, reject }));
      }
      return value;
    },
  };
  return provider;
}

function makeCache(provider, overrides = {}) {
  const clock = { t: MORNING };
  const logs = [];
  const cached = createWeatherCache({
    getWeather: provider.fn,
    now: () => clock.t,
    log: (line) => logs.push(line),
    ...overrides,
  });
  return { cached, clock, logs };
}

// A distinct 2 dp cell per index.
const cell = (i) => [10 + Math.floor(i / 100) / 100 + 0.001, 20 + (i % 100) / 100 + 0.001];

// --- rounding ---
test('two callers 0.004° apart share one provider call and the provider receives the rounded coordinates', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider);
  await cached(25.1551, 55.2077);
  await cached(25.1591, 55.2081);
  assert.equal(provider.calls.length, 1);
  assert.deepStrictEqual(provider.calls[0], [25.16, 55.21]);
});

// --- negative cache ---
test('a failure within 60 s makes no second provider call', async () => {
  const provider = makeProvider();
  provider.mode = 'fail';
  const { cached, clock } = makeCache(provider);
  await assert.rejects(() => cached(25.16, 55.21), UpstreamError);
  clock.t += NEGATIVE_TTL_MS - 1;
  await assert.rejects(() => cached(25.16, 55.21), UpstreamError);
  await assert.rejects(() => cached(25.16, 55.21, { origin: 'job' }), UpstreamError);
  assert.equal(provider.calls.length, 1, 'no provider call inside the negative-cache window');
  clock.t += 1;
  await assert.rejects(() => cached(25.16, 55.21), UpstreamError);
  assert.equal(provider.calls.length, 2, 'the window has passed — one retry');
});

test('the negative cache lasts 60 s', () => {
  assert.equal(NEGATIVE_TTL_MS, 60 * 1000);
});

test('a non-provider failure keeps its own type inside the negative-cache window', async () => {
  const failing = async () => { throw new Error('API_KEY environment variable is not set'); };
  const { cached } = makeCache({ fn: failing });
  await assert.rejects(() => cached(25.16, 55.21), (err) => !(err instanceof UpstreamError));
  await assert.rejects(() => cached(25.16, 55.21), (err) => !(err instanceof UpstreamError));
});

// --- global outside budget ---
test('the 61st outside miss in an hour is refused (502) while a job call for a new cell still fetches', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider, { outsideBudgetPerHour: 60 });
  for (let i = 0; i < 60; i++) await cached(...cell(i));
  assert.equal(provider.calls.length, 60);

  await assert.rejects(() => cached(...cell(60)), UpstreamError);
  assert.equal(provider.calls.length, 60, 'the refused miss made no provider call');

  await cached(...cell(61), { origin: 'job' });
  assert.equal(provider.calls.length, 61, 'jobs are never counted or refused');

  await cached(...cell(0));
  assert.equal(provider.calls.length, 61, 'a cache hit costs no budget and is still served');
});

test('the outside budget resets in the next hourly window', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider, { outsideBudgetPerHour: 2 });
  await cached(...cell(0));
  await cached(...cell(1));
  await assert.rejects(() => cached(...cell(2)), UpstreamError);
  clock.t += HOUR;
  await cached(...cell(2));
  assert.equal(provider.calls.length, 3);
});

test('a budget refusal serves the last good forecast to a caller that allows stale', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider, { outsideBudgetPerHour: 1 });
  await cached(25.16, 55.21);
  clock.t += TTL_MS + 30 * MINUTE; // expired, and a new hourly budget window
  await cached(...cell(0)); // spends the new window's budget
  const served = await cached(25.16, 55.21, { allowStale: true });
  assert.equal(served, morningForecast);
  await assert.rejects(() => cached(25.16, 55.21), UpstreamError, 'without allowStale the refusal is a 502');
});

// --- concurrency cap ---
test('the 9th concurrent outside miss is refused', async () => {
  const provider = makeProvider();
  provider.mode = 'hang';
  const { cached } = makeCache(provider, { outsideConcurrency: 8 });
  const inFlight = [];
  for (let i = 0; i < 8; i++) inFlight.push(cached(...cell(i)));
  assert.equal(provider.calls.length, 8);
  await assert.rejects(() => cached(...cell(8)), UpstreamError);
  assert.equal(provider.calls.length, 8);

  // A job is not capped; joining an in-flight cell is not a new miss.
  const job = cached(...cell(9), { origin: 'job' });
  const joined = cached(...cell(0));
  assert.equal(provider.calls.length, 9);

  provider.pending.forEach((p) => p.resolve(morningForecast));
  await Promise.all([...inFlight, job, joined]);

  provider.mode = 'ok';
  await cached(...cell(10));
  assert.equal(provider.calls.length, 10, 'slots are released when fetches settle');
});

// --- per-client miss limit ---
test('the 21st miss from one IP is refused, another IP is not (enforce)', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider, { missesPerClientPerHour: 20, clientLimitMode: 'enforce' });
  for (let i = 0; i < 20; i++) await cached(...cell(i), { clientKey: '203.0.113.7' });
  await assert.rejects(() => cached(...cell(20), { clientKey: '203.0.113.7' }), UpstreamError);
  await cached(...cell(21), { clientKey: '198.51.100.4' });
  assert.equal(provider.calls.length, 21);
});

test('two IPv6 addresses in one /64 share a bucket; another /64 does not', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider, { missesPerClientPerHour: 2, clientLimitMode: 'enforce' });
  await cached(...cell(0), { clientKey: '2001:db8:1:2::1' });
  await cached(...cell(1), { clientKey: '2001:0db8:0001:0002:ffff:eeee:dddd:cccc' });
  await assert.rejects(() => cached(...cell(2), { clientKey: '2001:db8:1:2:abcd::9' }), UpstreamError);
  await cached(...cell(3), { clientKey: '2001:db8:1:3::1' });
  assert.equal(provider.calls.length, 3);
});

test('in observe mode the per-client limit never refuses, and logs a count without any address', async () => {
  const provider = makeProvider();
  const { cached, clock, logs } = makeCache(provider, { missesPerClientPerHour: 2, clientLimitMode: 'observe' });
  for (let i = 0; i < 4; i++) await cached(...cell(i), { clientKey: '203.0.113.7' });
  assert.equal(provider.calls.length, 4);
  clock.t += HOUR;
  await cached(...cell(5), { clientKey: '203.0.113.7' });
  assert.ok(logs.some((l) => /over the per-client limit/.test(l)), `expected an over-limit log, got ${JSON.stringify(logs)}`);
  assert.ok(logs.some((l) => /distinct client keys/.test(l)));
  assert.ok(logs.every((l) => !l.includes('203.0.113')), 'no log line carries an address');
});

// --- the call with no options (a caller that passes only lat/lon) ---
test('a call with no options works, never throws synchronously, and counts as outside', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider, { outsideBudgetPerHour: 1 });
  let pending;
  assert.doesNotThrow(() => { pending = cached(25.16, 55.21); });
  assert.equal(await pending, morningForecast);
  let refused;
  assert.doesNotThrow(() => { refused = cached(...cell(0)); });
  await assert.rejects(refused, UpstreamError, 'the no-options miss spent the outside budget');
  await cached(...cell(1), { origin: 'job' });
});

test('callers with no clientKey skip the per-client count — they do not share one bucket', async () => {
  const provider = makeProvider();
  const { cached } = makeCache(provider, {
    missesPerClientPerHour: 1, clientLimitMode: 'enforce', outsideBudgetPerHour: 3,
  });
  await cached(...cell(0));
  await cached(...cell(1));
  await cached(...cell(2), {});
  assert.equal(provider.calls.length, 3, 'three key-less misses were not limited per client');
  await assert.rejects(() => cached(...cell(3)), UpstreamError, 'the global budget still applies');
});

// --- stale serving ---
test('stale is served at 5 h 59 m, not at 6 h 01 m', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider);
  await cached(25.16, 55.21);
  provider.mode = 'fail';

  clock.t = MORNING + 5 * HOUR + 59 * MINUTE;
  assert.equal(await cached(25.16, 55.21, { allowStale: true }), morningForecast);

  clock.t = MORNING + 6 * HOUR + 1 * MINUTE; // 12:01 in Dubai — same local day
  await assert.rejects(() => cached(25.16, 55.21, { allowStale: true }), UpstreamError);
});

test('the stale ceiling is 6 hours', () => {
  assert.equal(STALE_MAX_MS, 6 * HOUR);
});

test('stale is not served once the location\'s local day has rolled over', async () => {
  const evening = { forecastStart: '2026-08-01T18:00:00Z', timezone: 'Asia/Dubai', hours: [] }; // 22:00 local
  const provider = makeProvider(evening);
  const { cached, clock } = makeCache(provider);
  clock.t = Date.parse(evening.forecastStart);
  await cached(25.16, 55.21);
  provider.mode = 'fail';

  clock.t = Date.parse(evening.forecastStart) + 1 * HOUR + 30 * MINUTE; // 23:30 local
  assert.equal(await cached(25.16, 55.21, { allowStale: true }), evening);

  clock.t = Date.parse(evening.forecastStart) + 2 * HOUR + 30 * MINUTE; // 00:30 next day
  await assert.rejects(() => cached(25.16, 55.21, { allowStale: true }), UpstreamError);
});

test('stale is returned unchanged — no marker keys are added to the value', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider);
  await cached(25.16, 55.21);
  provider.mode = 'fail';
  clock.t += TTL_MS;
  const served = await cached(25.16, 55.21, { allowStale: true });
  assert.deepStrictEqual(Object.keys(served), ['forecastStart', 'timezone', 'hours']);
});

test('a job call never receives stale data (provider down → rejects)', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider);
  await cached(25.16, 55.21);
  provider.mode = 'fail';
  clock.t += TTL_MS;

  // The refresh fails: the job rejects even though it asked for stale.
  await assert.rejects(() => cached(25.16, 55.21, { origin: 'job', allowStale: true }), UpstreamError);
  // Inside the negative-cache window: same answer, no provider call.
  await assert.rejects(() => cached(25.16, 55.21, { origin: 'job' }), UpstreamError);
  // An outside caller in the same moment does get the last good forecast.
  assert.equal(await cached(25.16, 55.21, { allowStale: true }), morningForecast);
});

test('a job that joins an outside caller\'s failing fetch rejects; the outside caller gets stale', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider);
  await cached(25.16, 55.21);
  provider.mode = 'hang';
  clock.t += TTL_MS;
  const outside = cached(25.16, 55.21, { allowStale: true });
  const job = cached(25.16, 55.21, { origin: 'job' });
  assert.equal(provider.calls.length, 2, 'the job joined the in-flight fetch');
  provider.pending[0].reject(new UpstreamError('provider down'));
  assert.equal(await outside, morningForecast);
  await assert.rejects(job, UpstreamError);
});

// --- size cap and sweep ---
test('the cache never holds more than the cap and a swept entry\'s lastGood is gone', async () => {
  const provider = makeProvider();
  const { cached, clock } = makeCache(provider, { maxEntries: 5 });
  for (let i = 0; i < 12; i++) {
    await cached(...cell(i), { origin: 'job' });
    assert.ok(cached.size() <= 5, `size ${cached.size()} exceeds the cap`);
  }

  // Sweep: an entry whose last good forecast is past the stale ceiling goes
  // on the next insert, lastGood and all.
  const { cached: c2, clock: clock2 } = makeCache(provider, { maxEntries: 100 });
  await c2(25.16, 55.21);
  clock2.t += STALE_MAX_MS + 1;
  await c2(...cell(0));
  assert.equal(c2.size(), 1, 'the expired entry (and its lastGood) was swept');
  void clock;
});

test('the cache cap defaults to 1,000 entries', async () => {
  const { DEFAULT_MAX_ENTRIES } = require('../../src/services/weatherCache');
  assert.equal(DEFAULT_MAX_ENTRIES, 1000);
});
