const test = require('node:test');
const assert = require('node:assert/strict');
const { meteosourceAdapter } = require('../../src/weather/adapters/meteosource');
const { UpstreamError } = require('../../src/weather/UpstreamError');

// ---------- windSpeed (A1) ----------

test('windSpeed returns the value when wind.speed is present', () => {
  const h = { wind: { speed: 12 } };
  assert.equal(meteosourceAdapter.windSpeed(h), 12);
});

test('windSpeed returns null when wind is absent (A1)', () => {
  assert.equal(meteosourceAdapter.windSpeed({}), null);
});

test('windSpeed returns null when wind is null (A1)', () => {
  assert.equal(meteosourceAdapter.windSpeed({ wind: null }), null);
});

test('windSpeed returns null when wind.speed is absent (A1)', () => {
  assert.equal(meteosourceAdapter.windSpeed({ wind: {} }), null);
});

// ---------- rainFall (A2) ----------

test('rainFall returns the value when precipitation.total is present', () => {
  const h = { precipitation: { total: 1.4 } };
  assert.equal(meteosourceAdapter.rainFall(h), 1.4);
});

test('rainFall returns null when precipitation is absent (A2)', () => {
  assert.equal(meteosourceAdapter.rainFall({}), null);
});

test('rainFall returns null when precipitation is null (A2)', () => {
  assert.equal(meteosourceAdapter.rainFall({ precipitation: null }), null);
});

// ---------- cloudCover (A3) ----------

test('cloudCover returns the value when cloud_cover.total is present', () => {
  const h = { cloud_cover: { total: 25 } };
  assert.equal(meteosourceAdapter.cloudCover(h), 25);
});

test('cloudCover returns null when cloud_cover is absent (A3)', () => {
  assert.equal(meteosourceAdapter.cloudCover({}), null);
});

test('cloudCover returns null when cloud_cover is an object without .total (A3)', () => {
  // Previously returned the entire object → caused silent NaN comparisons downstream
  assert.equal(meteosourceAdapter.cloudCover({ cloud_cover: { low: 5, mid: 0 } }), null);
});

// ---------- uV (night-null guard) ----------

test('uV returns the value when uv_index is present', () => {
  assert.equal(meteosourceAdapter.uV({ uv_index: 6 }), 6);
});

test('uV preserves a real zero (daytime edge / dawn)', () => {
  assert.equal(meteosourceAdapter.uV({ uv_index: 0 }), 0);
});

test('uV defaults to 0 when uv_index is null (Meteosource returns null at night)', () => {
  // The live bug: uv_index is null after dark; passing it through emitted a null
  // that broke the iOS decoder (uV typed non-nullable) and blanked the dashboard.
  assert.equal(meteosourceAdapter.uV({ uv_index: null }), 0);
});

test('uV defaults to 0 when uv_index is absent', () => {
  assert.equal(meteosourceAdapter.uV({}), 0);
});

// ---------- timezone (ADR-0003 — location IANA zone) ----------

test('timezone extracts the top-level forecast-location IANA zone', () => {
  assert.equal(meteosourceAdapter.timezone({ timezone: 'Asia/Dubai' }), 'Asia/Dubai');
});

// ---------- forecastStart (ADR-0003 fetch wrinkle — local wall-time -> UTC-Z) ----------

test('forecastStart converts the provider local wall-time to UTC-Z via the zone', () => {
  // Under timezone=auto Meteosource returns LOCAL wall-time with no designator;
  // 16:00 Asia/Dubai (+4) is 12:00 UTC. Blind-appending Z would be 4h wrong.
  assert.equal(
    meteosourceAdapter.forecastStart({ date: '2026-06-19T16:00:00' }, 'Asia/Dubai'),
    '2026-06-19T12:00:00Z',
  );
});

test('forecastStart is idempotent on an already-UTC-Z timestamp', () => {
  assert.equal(
    meteosourceAdapter.forecastStart({ date: '2026-06-19T12:00:00Z' }, 'Asia/Dubai'),
    '2026-06-19T12:00:00Z',
  );
});

// A malformed/missing provider date is a malformed PAYLOAD → UpstreamError → 502,
// NOT an unparseable-date RangeError that escapes as a generic 500 (ADR-0004 typed
// error contract). This pins the guard that replaced the deleted hour() A4 check.
test('forecastStart throws UpstreamError when the provider date lacks a T separator (A4)', () => {
  assert.throws(() => meteosourceAdapter.forecastStart({ date: 'not a date' }, 'Asia/Dubai'), UpstreamError);
});

test('forecastStart throws UpstreamError when the provider date is missing (A4)', () => {
  assert.throws(() => meteosourceAdapter.forecastStart({}, 'Asia/Dubai'), UpstreamError);
});
