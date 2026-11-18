// The server edge: headers, CORS, the per-client request limiter and the
// proxy self-check, through createApp with an injected clock and logger.
// Requests use invalid /rating and /feedback bodies (→ 400), so no provider
// or database is ever reached.

const test = require('node:test');
const assert = require('node:assert/strict');
const supertest = require('supertest');

const app = require('../../src/server');
const { createApp } = require('../../src/server');

function makeApp({ env = {}, start = Date.parse('2026-08-01T10:00:00Z') } = {}) {
  const clock = { t: start };
  const logs = [];
  const server = createApp({ env, now: () => clock.t, log: (line) => logs.push(line) });
  return { server, clock, logs };
}

const badRating = (server, ip) => {
  const req = supertest(server).post('/api/v1/rating').send({});
  return ip ? req.set('X-Forwarded-For', ip) : req;
};
const badFeedback = (server) => supertest(server).post('/api/v1/feedback').send({});

test('X-Powered-By is absent', async () => {
  const res = await supertest(app).get('/health');
  assert.equal(res.status, 200);
  assert.equal(res.headers['x-powered-by'], undefined);
});

test('no Access-Control-Allow-Origin header, with or without an Origin', async () => {
  const plain = await supertest(app).get('/health');
  const withOrigin = await supertest(app).get('/health').set('Origin', 'https://example.com');
  const preflight = await supertest(app).options('/api/v1/rating')
    .set('Origin', 'https://example.com').set('Access-Control-Request-Method', 'POST');
  for (const res of [plain, withOrigin, preflight]) {
    assert.equal(res.headers['access-control-allow-origin'], undefined);
  }
});

test('the default mode is observe', async () => {
  const { server } = makeApp({ env: { RATE_LIMIT_PER_MINUTE: '1' } });
  await badRating(server);
  const res = await badRating(server);
  assert.equal(res.status, 400);
});

test('observe mode never returns 429 but logs', async () => {
  const { server, logs } = makeApp({ env: { RATE_LIMIT_MODE: 'observe' } });
  for (let i = 0; i < 125; i++) {
    const res = await badRating(server);
    assert.equal(res.status, 400, `request ${i + 1} must pass through in observe mode`);
  }
  assert.ok(logs.some((l) => /went over 120 requests/.test(l)), `expected a would-be-429 log, got ${JSON.stringify(logs.slice(-3))}`);
});

test('enforce mode returns the 429 envelope with Retry-After on the 121st request in a minute', async () => {
  const { server, clock } = makeApp({ env: { RATE_LIMIT_MODE: 'enforce' } });
  clock.t = Date.parse('2026-08-01T10:00:15Z');
  for (let i = 0; i < 120; i++) {
    assert.equal((await badRating(server)).status, 400);
  }
  const res = await badRating(server);
  assert.equal(res.status, 429);
  assert.deepStrictEqual(res.body, { errors: [{ message: 'Too many requests — try again shortly' }] });
  assert.equal(res.headers['retry-after'], '45');

  clock.t = Date.parse('2026-08-01T10:01:00Z');
  assert.equal((await badRating(server)).status, 400, 'the next minute opens a fresh window');
});

test('enforce: clients are limited separately (X-Forwarded-For, one trusted hop)', async () => {
  const { server } = makeApp({ env: { RATE_LIMIT_MODE: 'enforce', RATE_LIMIT_PER_MINUTE: '2' } });
  await badRating(server, '203.0.113.1');
  await badRating(server, '203.0.113.1');
  assert.equal((await badRating(server, '203.0.113.1')).status, 429);
  assert.equal((await badRating(server, '198.51.100.2')).status, 400);
  // A spoofed leading entry does not change the key — only the last hop counts.
  assert.equal((await badRating(server, '192.0.2.99, 203.0.113.1')).status, 429);
});

test('enforce: the hourly limit is env-tunable', async () => {
  const { server, clock } = makeApp({ env: { RATE_LIMIT_MODE: 'enforce', RATE_LIMIT_PER_HOUR: '3' } });
  for (let i = 0; i < 3; i++) {
    clock.t += 2 * 60 * 1000;
    assert.equal((await badRating(server)).status, 400);
  }
  assert.equal((await badRating(server)).status, 429);
});

test('enforce: /api/v1/feedback is limited to 30 per hour', async () => {
  const { server, clock } = makeApp({ env: { RATE_LIMIT_MODE: 'enforce' } });
  for (let i = 0; i < 30; i++) {
    clock.t += 60 * 1000; // stay under the per-minute limit
    assert.equal((await badFeedback(server)).status, 400);
  }
  const res = await badFeedback(server);
  assert.equal(res.status, 429);
  assert.ok(Number(res.headers['retry-after']) > 0);
  assert.equal((await badRating(server)).status, 400, 'other routes are not held by the feedback limit');
});

test('GET /health is never limited', async () => {
  const { server } = makeApp({ env: { RATE_LIMIT_MODE: 'enforce', RATE_LIMIT_PER_MINUTE: '1' } });
  for (let i = 0; i < 3; i++) assert.equal((await supertest(server).get('/health')).status, 200);
});

test('the self-check line contains no IP', async () => {
  const { server, logs } = makeApp();
  await badRating(server, '203.0.113.9, 100.64.0.7');
  await badRating(server, '198.51.100.23');
  const checks = logs.filter((l) => l.startsWith('proxy self-check'));
  assert.equal(checks.length, 2);
  assert.match(checks[0], /x-forwarded-for entries=2, req\.ip private=true/);
  assert.match(checks[1], /x-forwarded-for entries=1, req\.ip private=false/);
  for (const line of logs) {
    assert.doesNotMatch(line, /\d+\.\d+\.\d+\.\d+/, `log line carries an address: ${line}`);
  }
});

test('the self-check stops after the first 50 API requests and ignores /health', async () => {
  const { server, logs } = makeApp();
  await supertest(server).get('/health');
  for (let i = 0; i < 52; i++) await badRating(server);
  assert.equal(logs.filter((l) => l.startsWith('proxy self-check')).length, 50);
});

test('each limiter window logs its count of distinct client keys, without addresses', async () => {
  const { server, clock, logs } = makeApp();
  await badRating(server, '203.0.113.1');
  await badRating(server, '198.51.100.2');
  clock.t += 60 * 1000;
  await badRating(server, '203.0.113.1');
  const summary = logs.find((l) => /api-minute: window closed/.test(l));
  assert.ok(summary, `expected a window summary, got ${JSON.stringify(logs)}`);
  assert.match(summary, /2 distinct client keys/);
  for (const line of logs) assert.doesNotMatch(line, /\d+\.\d+\.\d+\.\d+/);
});
