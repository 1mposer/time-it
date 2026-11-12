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

// ---------- uV (night = 0, missing daylight UV = unknown) ----------
//
// Meteosource returns uv_index: null at night (genuinely 0), but it also stops
// sending UV past its horizon (~day 5, build-9 addendum "New on build 9" #1) —
// a `?? 0` there turned a missing noon reading into a 0 that passes any max
// (a false Perfect). Daylight comes from the day's astro.sun.

const dubaiSun = { rise: '2026-11-16T06:30:00', set: '2026-11-16T17:35:00', alwaysUp: false, alwaysDown: false };

test('uV returns the value when uv_index is present', () => {
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T12:00:00', uv_index: 6 }, dubaiSun), 6);
});

test('uV preserves a real zero (daytime edge / dawn)', () => {
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T12:00:00', uv_index: 0 }, dubaiSun), 0);
});

test('uV is 0 when uv_index is null at night (Meteosource returns null after dark)', () => {
  // The 2026-07-12 decode bug: a night null must stay a real 0 reading.
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T22:00:00', uv_index: null }, dubaiSun), 0);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T03:00:00' }, dubaiSun), 0);
});

test('uV is null (unknown) when uv_index is missing during full daylight', () => {
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T12:00:00', uv_index: null }, dubaiSun), null);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T09:00:00' }, dubaiSun), null);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T15:00:00' }, dubaiSun), null);
});

test('uV keeps 0 for the twilight hours the sun only partly covers', () => {
  // 06:00–07:00 starts before the 06:30 sunrise; 17:00–18:00 ends after the
  // 17:35 sunset — UV there is ~0 and the provider's own dawn readings are ~0.1.
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T06:00:00', uv_index: null }, dubaiSun), 0);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T17:00:00', uv_index: null }, dubaiSun), 0);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T06:30:00', uv_index: null }, dubaiSun), null,
    'an hour fully inside sun-up is daylight');
});

test('uV is null when the day has no sun data, and follows polar day/night', () => {
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T03:00:00', uv_index: null }, undefined), null,
    'no astro for the day → unknown, never a passing 0');
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T03:00:00' }, { rise: null, set: null, alwaysUp: true, alwaysDown: false }), null);
  assert.equal(meteosourceAdapter.uV({ date: '2026-11-16T12:00:00' }, { rise: null, set: null, alwaysUp: false, alwaysDown: true }), 0);
});

test('sunByDay reads daily astro.sun keyed on the local day', () => {
  const byDay = meteosourceAdapter.sunByDay({ daily: { data: [
    { day: '2026-11-16', astro: { sun: { rise: '2026-11-16T06:30:00', set: '2026-11-16T17:35:00', always_up: false, always_down: false } } },
    { day: '2026-11-17', astro: { moon: { phase: 'new_moon' } } },
  ] } });
  assert.deepEqual(byDay, { '2026-11-16': dubaiSun });
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

// ---------- moon (#27 — daily astro, not a top-level section) ----------

// Live shape (verified 2026-09-15 against /standard/point, sections=all): no
// top-level `astro`; the phase sits at daily.data[].astro.moon.phase keyed by
// daily.data[].day ('YYYY-MM-DD'), one of four snake_case names.
test('moonPhaseByDay reads daily.data[].astro.moon.phase keyed on the local day', () => {
  const res = { daily: { data: [
    { day: '2026-09-15', astro: { sun: {}, moon: { phase: 'new_moon' } } },
    { day: '2026-09-16', astro: { sun: {}, moon: { phase: 'first_quarter' } } },
  ] } };
  assert.deepStrictEqual(meteosourceAdapter.moonPhaseByDay(res), {
    '2026-09-15': 'new moon',
    '2026-09-16': 'first quarter',
  });
});

test('moonPhaseByDay skips days without a phase and tolerates a missing daily section', () => {
  assert.deepStrictEqual(meteosourceAdapter.moonPhaseByDay({}), {});
  assert.deepStrictEqual(meteosourceAdapter.moonPhaseByDay({ daily: null }), {});
  const res = { daily: { data: [
    { day: '2026-09-15' },
    { day: '2026-09-16', astro: { moon: { phase: null } } },
    { day: '2026-09-17', astro: { moon: { phase: 'full_moon' } } },
  ] } };
  assert.deepStrictEqual(meteosourceAdapter.moonPhaseByDay(res), { '2026-09-17': 'full moon' });
});

test('moonPhaseByDay never reads the old top-level astro shape (the #27 regression)', () => {
  const res = { astro: { data: [{ moon_phase: 'waxing crescent' }] } };
  assert.deepStrictEqual(meteosourceAdapter.moonPhaseByDay(res), {});
});

test('localDate is the hourly row local calendar date — the join key for the moon map', () => {
  assert.equal(meteosourceAdapter.localDate({ date: '2026-09-15T18:00:00' }), '2026-09-15');
  assert.equal(meteosourceAdapter.localDate({}), null);
});
