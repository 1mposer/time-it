const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createFeedbackRouter = require('../../src/routes/feedback');

// Stateful fake db: interprets exactly the queries the router issues. The
// count query returns a JS number (the router casts count(*)::int, which the
// pg driver returns as a number, unlike the bare bigint-as-string count).
function makeFakeDb({ recentCount = 0 } = {}) {
  const inserted = [];
  const queries = [];
  let count = recentCount;
  return {
    inserted,
    queries,
    query: async (text, params) => {
      queries.push({ text, params });
      if (text.includes('SELECT count(*)')) {
        return { rows: [{ count }] };
      }
      if (text.includes('INSERT INTO suggestions')) {
        const [deviceId, message, appVersion, build, iosVersion] = params;
        inserted.push({ device_id: deviceId, message, app_version: appVersion, build, ios_version: iosVersion });
        count += 1;
        return { rows: [] };
      }
      throw new Error(`fake db: unexpected query: ${text}`);
    },
  };
}

function makeApp(db = makeFakeDb()) {
  const app = express();
  app.use(express.json());
  app.use('/api/v1', createFeedbackRouter({ db }));
  return { app, db };
}

const DEVICE_ID = '9f3a0c1e-4b7d-4a2e-8f6c-1d2e3f4a5b6c';
function validBody(overrides = {}) {
  return {
    deviceId: DEVICE_ID,
    message: 'The dashboard cards could show wind direction too.',
    appVersion: '1.0',
    build: '7',
    iosVersion: '17.5',
    ...overrides,
  };
}

const post = (app, body) => supertest(app).post('/api/v1/feedback').send(body);

// --- happy path ---
test('POST stores the suggestion: 204 no body, full row shape, message trimmed', async () => {
  const { app, db } = makeApp();
  const res = await post(app, validBody({ message: '  Add wind direction.  ' }));
  assert.equal(res.status, 204);
  assert.deepStrictEqual(res.body, {});
  assert.deepStrictEqual(db.inserted, [{
    device_id: DEVICE_ID,
    message: 'Add wind direction.',
    app_version: '1.0',
    build: '7',
    ios_version: '17.5',
  }]);
});

// --- validation 400s (uniform { errors[] } envelope, atomic collect) ---
test('each required field missing/empty/non-string → 400 with that field as path', async () => {
  const { app } = makeApp();
  for (const field of ['deviceId', 'message', 'appVersion', 'build', 'iosVersion']) {
    for (const bad of [undefined, '', 42]) {
      const body = validBody();
      if (bad === undefined) delete body[field]; else body[field] = bad;
      const res = await post(app, body);
      assert.equal(res.status, 400, `${field}=${JSON.stringify(bad)}`);
      assert.ok(res.body.errors.some((e) => e.path === field), `${field} path present`);
    }
  }
});

test('whitespace-only message → 400 (a blank suggestion is not a suggestion)', async () => {
  const { app, db } = makeApp();
  const res = await post(app, validBody({ message: '   \n  ' }));
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'message'));
  assert.equal(db.inserted.length, 0);
});

test('over-length message (>1000 chars) and over-length metadata (>64) → 400', async () => {
  const { app } = makeApp();
  let res = await post(app, validBody({ message: 'x'.repeat(1001) }));
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'message' && e.message.includes('1000')));

  res = await post(app, validBody({ build: 'b'.repeat(65) }));
  assert.equal(res.status, 400);
  assert.ok(res.body.errors.some((e) => e.path === 'build' && e.message.includes('64')));

  // Boundary: exactly at the caps is valid.
  res = await post(app, validBody({ message: 'x'.repeat(1000), build: 'b'.repeat(64) }));
  assert.equal(res.status, 204);
});

test('validation is atomic — every failure collected in one 400', async () => {
  const { app } = makeApp();
  const res = await post(app, { message: '', build: 7 });
  assert.equal(res.status, 400);
  const paths = res.body.errors.map((e) => e.path);
  for (const p of ['deviceId', 'message', 'appVersion', 'build', 'iosVersion']) {
    assert.ok(paths.includes(p), `collected ${p}`);
  }
});

test('validation runs BEFORE any db query — a bad body costs nothing', async () => {
  const { app, db } = makeApp();
  await post(app, { message: '' });
  assert.equal(db.queries.length, 0);
});

// --- per-device daily ceiling ---
test('at the 20/day ceiling → 429 with the uniform envelope, nothing inserted', async () => {
  const { app, db } = makeApp(makeFakeDb({ recentCount: 20 }));
  const res = await post(app, validBody());
  assert.equal(res.status, 429);
  assert.deepStrictEqual(res.body, {
    errors: [{ message: 'Too many suggestions today — try again tomorrow' }],
  });
  assert.equal(db.inserted.length, 0);
});

test('the ceiling is a real sequence: 20 accepted, the 21st rejected', async () => {
  const { app, db } = makeApp();
  for (let i = 0; i < 20; i++) {
    const res = await post(app, validBody({ message: `suggestion ${i}` }));
    assert.equal(res.status, 204, `suggestion ${i} accepted`);
  }
  const res = await post(app, validBody({ message: 'one too many' }));
  assert.equal(res.status, 429);
  assert.equal(db.inserted.length, 20);
});

// --- failure mapping ---
test('db failure → 500 with the uniform envelope', async () => {
  const failingDb = { query: async () => { throw new Error('connection refused'); } };
  const { app } = makeApp(failingDb);
  const res = await post(app, validBody());
  assert.equal(res.status, 500);
  assert.deepStrictEqual(res.body, { errors: [{ message: 'Internal server error' }] });
});
