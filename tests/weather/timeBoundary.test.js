const test = require('node:test');
const assert = require('node:assert/strict');
const { tagLocalDays, zonedWallTimeToUtcIso } = require('../../src/weather/timeBoundary');

// ADR-0003 worked example (real probe numbers): Meteosource `flexi` returned
// 164 hourly entries starting 2026-06-19T12:00:00Z = 16:00 in Asia/Dubai.
// Bucketed by local calendar day:
//   day 0 = 16:00->23:00 local = 8 hours  (indices 0-7,   partial today)
//   days 1-6 = 24 h each       = 144 hours (indices 8-151)
//   day 7 = 00:00->11:00 local = 12 hours (indices 152-163, partial tail)
// Total: 8 buckets from 164 hours.
const FORECAST_START = '2026-06-19T12:00:00Z';
const TIMEZONE = 'Asia/Dubai';

// Hour content is irrelevant to bucketing — only forecastStart + index + zone matter.
function makeHours(count) {
  return Array.from({ length: count }, () => ({ temp: 20 }));
}

// Distinct localDay values in array order, with the run-length (hour count) of each.
function bucketShape(hours) {
  const buckets = [];
  for (const h of hours) {
    const last = buckets[buckets.length - 1];
    if (last && last.localDay === h.localDay) last.count++;
    else buckets.push({ localDay: h.localDay, count: 1 });
  }
  return buckets;
}

test('tagLocalDays tags each hour with the forecast-location local calendar day', () => {
  const tagged = tagLocalDays(makeHours(164), FORECAST_START, TIMEZONE);

  // index 0 = 16:00 local on 2026-06-19; index 7 = 23:00 local same day.
  assert.equal(tagged[0].localDay, '2026-06-19');
  assert.equal(tagged[7].localDay, '2026-06-19');
  // index 8 = 00:00 local crosses into the next calendar day.
  assert.equal(tagged[8].localDay, '2026-06-20');
  // index 152 = 00:00 local on the tail day; 163 = 11:00 local same day.
  assert.equal(tagged[152].localDay, '2026-06-26');
  assert.equal(tagged[163].localDay, '2026-06-26');
});

test('the 164-hour horizon resolves to 8 local-day buckets of 8/24x6/12 hours', () => {
  const tagged = tagLocalDays(makeHours(164), FORECAST_START, TIMEZONE);
  const shape = bucketShape(tagged);

  assert.deepStrictEqual(shape.map((b) => b.count), [8, 24, 24, 24, 24, 24, 24, 12]);
  assert.deepStrictEqual(shape.map((b) => b.localDay), [
    '2026-06-19', '2026-06-20', '2026-06-21', '2026-06-22',
    '2026-06-23', '2026-06-24', '2026-06-25', '2026-06-26',
  ]);
});

test('tagLocalDays does not mutate the input hours and preserves existing fields', () => {
  const input = makeHours(3);
  const tagged = tagLocalDays(input, FORECAST_START, TIMEZONE);
  assert.equal(input[0].localDay, undefined, 'input hour was mutated');
  assert.equal(tagged[0].temp, 20, 'existing field dropped');
});

// zonedWallTimeToUtcIso — the fetch-wrinkle reconciliation (ADR-0003). Under
// timezone=auto Meteosource returns LOCAL wall-time with no Z/offset; the
// adapter converts it to the UTC-Z forecastStart contract via the location zone.
// Blind-appending Z would mislabel 16:00 Dubai as 16:00 UTC (4h wrong).
test('zonedWallTimeToUtcIso converts a local wall-time to UTC-Z via the zone', () => {
  // 16:00 Asia/Dubai (+4) = 12:00 UTC — the ADR-0003 worked example, inverted.
  assert.equal(zonedWallTimeToUtcIso('2026-06-19T16:00:00', 'Asia/Dubai'), '2026-06-19T12:00:00Z');
  // 11:00 Asia/Dubai = 07:00 UTC — the live probe's first timestamp.
  assert.equal(zonedWallTimeToUtcIso('2026-06-22T11:00:00', 'Asia/Dubai'), '2026-06-22T07:00:00Z');
});

test('zonedWallTimeToUtcIso emits no milliseconds (matches the forecastStart contract)', () => {
  assert.match(zonedWallTimeToUtcIso('2026-06-22T11:00:00', 'Asia/Dubai'), /T\d{2}:\d{2}:\d{2}Z$/);
});

test('zonedWallTimeToUtcIso trusts an already-zoned timestamp (idempotent on UTC-Z)', () => {
  assert.equal(zonedWallTimeToUtcIso('2026-06-19T12:00:00Z', 'Asia/Dubai'), '2026-06-19T12:00:00Z');
});

// Landmine guard (ADR-0003): localDay must be computed from the UTC instant.
// A non-UTC server host must not shift the buckets — same instant, same zone,
// same answer regardless of where the test runs.
test('localDay is computed from the UTC instant, not the host timezone', () => {
  // 2026-06-19T20:00:00Z = 00:00 next day in Asia/Dubai (+4) -> already 2026-06-20.
  const tagged = tagLocalDays(makeHours(1), '2026-06-19T20:00:00Z', TIMEZONE);
  assert.equal(tagged[0].localDay, '2026-06-20');
});
