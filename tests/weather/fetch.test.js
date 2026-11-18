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

// A provider that accepts the connection and never answers must not hold the
// caller (and the shared cache's in-flight promise) open: the request is
// aborted after PROVIDER_TIMEOUT_MS and surfaces as UpstreamError (→ 502).
test('a stalled provider rejects with UpstreamError after the timeout (fake timer)', async (t) => {
  t.after(restoreFetch);
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { PROVIDER_TIMEOUT_MS } = require('../../src/weather/fetch');
  global.fetch = (_url, { signal } = {}) => new Promise((_resolve, reject) => {
    signal?.addEventListener('abort', () => reject(signal.reason ?? new Error('aborted')));
  });
  let settled = null;
  const pending = fetchWeather({ lat: 0, lon: 0 }).then(
    () => { settled = 'resolved'; },
    (err) => { settled = err; },
  );
  t.mock.timers.tick(PROVIDER_TIMEOUT_MS - 1);
  await new Promise(setImmediate);
  assert.equal(settled, null, 'still waiting one millisecond before the timeout');
  t.mock.timers.tick(1);
  await pending;
  assert.ok(settled instanceof UpstreamError, `expected UpstreamError, got ${settled}`);
});

test('the provider timeout is 8 seconds', () => {
  const { PROVIDER_TIMEOUT_MS } = require('../../src/weather/fetch');
  assert.equal(PROVIDER_TIMEOUT_MS, 8000);
});

test('an unparseable provider body is an UpstreamError, not a generic error', async (t) => {
  t.after(restoreFetch);
  global.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => { throw new SyntaxError('Unexpected token < in JSON at position 0'); },
  });
  await assert.rejects(() => fetchWeather({ lat: 0, lon: 0 }), UpstreamError);
});
