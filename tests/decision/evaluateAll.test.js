const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluateAll } = require("../../src/decision/evaluateAll");
const { tagLocalDays } = require("../../src/weather/timeBoundary");

// forecastStart 20:00Z = 00:00 next day in Asia/Dubai (+4), so index 0 lands on
// a local-midnight boundary and the horizon splits into clean full calendar days:
//   day 0 = 2026-06-20 (indices 0-23), day 1 = 2026-06-21 (indices 24-47).
// Clean 24/24 keeps the global-offset assertions exact and hand-checkable.
const FORECAST_START = '2026-06-19T20:00:00Z';
const TIMEZONE = 'Asia/Dubai';

// Activities are now CALLER-SUPPLIED (ADR-0005): evaluateAll(hours, activities).
// These mirror the shape the route validates and forwards. All metrics used here
// are LIVE so the fixtures double as valid request bodies.
const VOLLEYBALL = {
  id: 'volleyball',
  label: 'Volleyball',
  displayMetrics: ['temp', 'windSpeed', 'dustAlert'],
  thresholds: {
    temp: { min: 15, max: 35, required: true },
    windSpeed: { max: 15, required: false },
    dustAlert: { type: 'flag', forbidTrue: true, required: true },
  },
};
const SHADE = {
  id: 'shade-walk',
  label: 'Shade Walk',
  displayMetrics: ['temp'],
  thresholds: { temp: { min: 15, max: 35, required: true } },
};

function baseHour(overrides = {}) {
  return {
    temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false, ...overrides,
  };
}

// `perIndex(i)` may return per-hour overrides; hours are then tagged with their
// forecast-location localDay exactly as the real pipeline does before evaluateAll.
function makeHours(count, perIndex = () => ({})) {
  const hours = Array.from({ length: count }, (_, i) => baseHour(perIndex(i)));
  return tagLocalDays(hours, FORECAST_START, TIMEZONE);
}

// Same, but with an arbitrary forecastStart so night-stitch fixtures can pick a
// local start hour that exercises partial days and the orphan-morning case.
function makeHoursAt(forecastStart, count, perIndex = () => ({})) {
  const hours = Array.from({ length: count }, (_, i) => baseHour(perIndex(i)));
  return tagLocalDays(hours, forecastStart, TIMEZONE);
}

test("evaluateAll returns one result per caller-supplied activity, in order", () => {
  const results = evaluateAll(makeHours(48), [VOLLEYBALL, SHADE]);
  assert.ok(Array.isArray(results));
  assert.equal(results.length, 2);
  assert.deepStrictEqual(results.map((r) => r.activityId), ['volleyball', 'shade-walk']);
});

test("every result carries activityId, label, displayMetrics, days[] (no top-level window)", () => {
  const results = evaluateAll(makeHours(48), [VOLLEYBALL, SHADE]);
  for (const result of results) {
    assert.ok("activityId" in result);
    assert.ok("label" in result);
    assert.ok("displayMetrics" in result);
    assert.ok(Array.isArray(result.days));
    assert.equal("rating" in result, false, `top-level rating must be removed on ${result.activityId}`);
    assert.equal("startIndex" in result, false, `top-level startIndex must be removed on ${result.activityId}`);
  }
});

test("displayMetrics is echoed from the caller-supplied activity", () => {
  const [vb] = evaluateAll(makeHours(48), [VOLLEYBALL]);
  assert.deepStrictEqual(vb.displayMetrics, ['temp', 'windSpeed', 'dustAlert']);
});

test("days[] is one dense entry per local calendar day, dayIndex contiguous from 0", () => {
  const results = evaluateAll(makeHours(48), [VOLLEYBALL, SHADE]);
  for (const result of results) {
    assert.equal(result.days.length, 2, `${result.activityId} should bucket into 2 local days`);
    result.days.forEach((day, i) => assert.equal(day.dayIndex, i));
  }
});

// CONSTRAINT (ADR-0004 pin 1): startIndex/endIndex are GLOBAL indices into hours[],
// never day-relative. A window on day >= 1 is the only thing that catches a missing
// per-day offset — day 0's offset is 0 and would pass even if the offset were dropped.
test("per-day window indices are global, not day-relative (offset applied on day >= 1)", () => {
  const [vb] = evaluateAll(makeHours(48), [VOLLEYBALL]);
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: "perfect", startIndex: 0,  endIndex: 24, duration: 24 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: "perfect", startIndex: 24, endIndex: 48, duration: 24 });
});

// A non-qualifying day keeps its slot: { dayIndex, rating: null }, window triplet ABSENT.
test("null day keeps its slot with the window fields absent", () => {
  const hours = makeHours(48, (i) => (i < 24 ? { dustAlert: true } : {}));
  const [vb] = evaluateAll(hours, [VOLLEYBALL]);
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: null });
  assert.equal(vb.days[1].rating, "perfect");
  assert.equal(vb.days[1].startIndex, 24);
});

// Optional-threshold breach downgrades perfect -> good, asserted per day.
test('"good" path: optional windSpeed exceeded downgrades per day', () => {
  const [vb] = evaluateAll(makeHours(48, () => ({ windSpeed: 20 })), [VOLLEYBALL]);
  assert.equal(vb.days[0].rating, "good");
  assert.equal(vb.days[1].rating, "good");
});

// A required flag breach fails the affected day.
test("dustAlert true yields null rating on the affected day only", () => {
  const hours = makeHours(48, (i) => (i < 24 ? { dustAlert: true } : {}));
  const [vb] = evaluateAll(hours, [VOLLEYBALL]);
  assert.equal(vb.days[0].rating, null);
  assert.equal(vb.days[1].rating, "perfect");
});

// Seam #2 (ADR-0003): hours MUST be pre-tagged with localDay. UNTAGGED hours
// collapse to a single bucket — this pins that the contract is to pass tagged hours.
test("tagged hours bucket per day; the localDay tag drives bucketing", () => {
  const tagged = makeHours(48);
  const [vb] = evaluateAll(tagged, [VOLLEYBALL]);
  assert.equal(vb.days.length, 2);
});

// ───────────────────────── time-of-day window + night-stitch ─────────────────────────
// FORECAST_START 20:00Z = 00:00 Asia/Dubai, so global index === localHour within a day:
//   day 0 = indices 0-23, day 1 = 24-47, day 2 = 48-71. Keeps window math hand-checkable.

const MIDDAY = {
  id: 'midday', label: 'Midday',
  displayMetrics: ['temp'],
  thresholds: { temp: { min: 15, max: 35, required: true } },
  window: { startHour: 9, endHour: 17 }, // same-day, half-open [9,17) -> 8 eligible hours
};
const NIGHT = {
  id: 'star', label: 'Stargazing',
  displayMetrics: ['temp', 'cloudCover'],
  thresholds: { temp: { min: 5, max: 35, required: true }, cloudCover: { max: 30, required: true } },
  window: { startHour: 22, endHour: 2 }, // wraps midnight -> night-stitch
};

// Same-day window: each calendar day is filtered to [startHour, endHour); days.length
// is unchanged (one per calendar day) and indices are GLOBAL.
test('same-day window filters each day to [startHour,endHour) with global indices', () => {
  const [r] = evaluateAll(makeHours(48), [MIDDAY]);
  assert.equal(r.days.length, 2);
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 9,  endIndex: 17, duration: 8 });
  assert.deepStrictEqual(r.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 33, endIndex: 41, duration: 8 });
});

test('same-day window: failures OUTSIDE the window are ignored; INSIDE fail the day', () => {
  // temp=100 at indices 0-8 is outside day-0 window [9,17) -> day 0 still perfect.
  const outside = evaluateAll(makeHours(48, (i) => (i <= 8 ? { temp: 100 } : {})), [MIDDAY])[0];
  assert.equal(outside.days[0].rating, 'perfect');
  // temp=100 at indices 9-16 IS the day-0 window -> day 0 is null, day 1 unaffected.
  const inside = evaluateAll(makeHours(48, (i) => (i >= 9 && i <= 16 ? { temp: 100 } : {})), [MIDDAY])[0];
  assert.deepStrictEqual(inside.days[0], { dayIndex: 0, rating: null });
  assert.equal(inside.days[1].rating, 'perfect');
});

// Wrapped window stitches one local-midnight crossing per night; dayIndex is the
// EVENING's calendar day, and startIndex/endIndex are global across the boundary.
test('wrapped window stitches a night across midnight (clean fixture, global indices)', () => {
  const [r] = evaluateAll(makeHours(72), [NIGHT]);
  assert.equal(r.days.length, 3);
  // night 0 = day0 22:00,23:00 (idx 22,23) + day1 00:00,01:00 (idx 24,25)
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 22, endIndex: 26, duration: 4 });
  assert.deepStrictEqual(r.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 46, endIndex: 50, duration: 4 });
  // tail night: day2 evening only (no day3 morning in the horizon) -> 2 hours
  assert.deepStrictEqual(r.days[2], { dayIndex: 2, rating: 'perfect', startIndex: 70, endIndex: 72, duration: 2 });
});

// The ADR-0004 amendment core claim: a nocturnal activity buckets by NIGHT while a
// diurnal one buckets by calendar day, so days.length differs PER ACTIVITY in one
// response. Realistic 16:00-start horizon ending mid-morning -> tail has no evening.
test('days.length is per-activity: nocturnal is one shorter than diurnal on a partial-morning tail', () => {
  const hours = makeHoursAt('2026-06-19T12:00:00Z', 60); // 16:00 local start; day3 = 00:00-03:00
  const [diurnal, nocturnal] = evaluateAll(hours, [SHADE, NIGHT]);
  assert.equal(diurnal.days.length, 4, 'diurnal: 4 calendar days (0..3)');
  assert.equal(nocturnal.days.length, 3, 'nocturnal: 3 nights (0..2) — tail day has no evening');
  nocturnal.days.forEach((d, i) => assert.equal(d.dayIndex, i)); // still dense from 0
  // night 2 = day2 22:00,23:00 (idx 54,55) + day3 00:00,01:00 (idx 56,57)
  assert.deepStrictEqual(nocturnal.days[2], { dayIndex: 2, rating: 'perfect', startIndex: 54, endIndex: 58, duration: 4 });
});

// Orphan morning: day-0 early hours whose evening is pre-horizon belong to no night
// and are DROPPED (not a separate day-0 window). Start 01:00 local -> idx 0 = 01:00.
test('orphan morning (pre-horizon evening) is dropped, not made its own night', () => {
  const hours = makeHoursAt('2026-06-19T21:00:00Z', 48); // 01:00 local start
  const [r] = evaluateAll(hours, [NIGHT]);
  // idx 0 is 01:00 (< endHour 2) but its evening is before the horizon -> dropped.
  // night 0's evening is day0 22:00,23:00 = idx 21,22; morning day1 00:00,01:00 = idx 23,24.
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 21, endIndex: 25, duration: 4 });
});

// A night with no qualifying hours keeps its dense slot as a null day.
test('a non-qualifying night keeps its slot with rating null', () => {
  // Fail cloudCover only during night 0's hours (idx 22-25).
  const hours = makeHours(72, (i) => (i >= 22 && i <= 25 ? { cloudCover: 90 } : {}));
  const [r] = evaluateAll(hours, [NIGHT]);
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: null });
  assert.equal(r.days[1].rating, 'perfect');
});
