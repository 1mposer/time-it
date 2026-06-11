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

// ---------- forecastStart (B4 — unambiguous UTC) ----------

test('forecastStart appends Z to make the timestamp unambiguous UTC (B4)', () => {
  // Meteosource returns dates without a timezone designator. With timezone=UTC forced,
  // the backend appends 'Z' so iOS ISO 8601 parsers can decode it without custom formatting.
  assert.equal(meteosourceAdapter.forecastStart({ date: '2026-06-10T14:00:00' }), '2026-06-10T14:00:00Z');
});

test('forecastStart does not double-append Z when already present (B4)', () => {
  assert.equal(meteosourceAdapter.forecastStart({ date: '2026-06-10T14:00:00Z' }), '2026-06-10T14:00:00Z');
});

// ---------- hour (A4) ----------

test('hour parses the hour from a valid ISO 8601 date', () => {
  assert.equal(meteosourceAdapter.hour({ date: '2026-06-10T14:00:00' }), 14);
});

test('hour throws UpstreamError when date lacks T separator (A4)', () => {
  assert.throws(
    () => meteosourceAdapter.hour({ date: '2026-06-10 14:00:00' }),
    UpstreamError,
  );
});

test('hour throws UpstreamError when date is missing entirely (A4)', () => {
  assert.throws(
    () => meteosourceAdapter.hour({}),
    UpstreamError,
  );
});
