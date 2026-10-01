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
  // score (ADR-0011): temp 25 is the centre of [15,35] -> 100; windSpeed 10 is
  // inside one-sided max 15 -> 100; dustAlert false -> 100. Every hour 100.
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: "perfect", startIndex: 0,  endIndex: 24, duration: 24, score: 100 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: "perfect", startIndex: 24, endIndex: 48, duration: 24, score: 100 });
});

// A non-qualifying day keeps its slot: { dayIndex, rating: null }, window triplet
// ABSENT — but `score` is still there (ADR-0011: score and rating are independent).
test("null day keeps its slot with the window fields absent", () => {
  const hours = makeHours(48, (i) => (i < 24 ? { dustAlert: true } : {}));
  const [vb] = evaluateAll(hours, [VOLLEYBALL]);
  // Every day-0 hour trips the REQUIRED dustAlert flag -> the rating is null.
  // Score (amended ADR-0011, 2026-10-01: a required miss scores 0 for that
  // metric only, the hour still averages): temp 25 = centre of [15,35] -> 100;
  // windSpeed 10 <= max 15 -> 100; dustAlert true -> 0. Hour = (100+100+0)/3 =
  // 200/3 = 66.66...; every hour identical -> day 66.66... -> 67 (was 1 under
  // the retired zero-the-hour rule). Never null: the bucket has hours.
  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: null, score: 67 });
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

// Seam #2 (ADR-0003): hours MUST be pre-tagged with localDay/localHour. The
// guard makes an untagged batch fail loudly instead of silently collapsing to
// a single bucket rated as one "day".
test("tagged hours bucket per day; the localDay tag drives bucketing", () => {
  const tagged = makeHours(48);
  const [vb] = evaluateAll(tagged, [VOLLEYBALL]);
  assert.equal(vb.days.length, 2);
});

test("untagged hours are rejected, not silently collapsed", () => {
  const untagged = Array.from({ length: 48 }, () => baseHour());
  assert.throws(() => evaluateAll(untagged, [VOLLEYBALL]), /tagLocalDays/);
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
  // score: temp 25 is the centre of [15,35] in all 8 window hours -> 100.
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 9,  endIndex: 17, duration: 8, score: 100 });
  assert.deepStrictEqual(r.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 33, endIndex: 41, duration: 8, score: 100 });
});

test('same-day window: failures OUTSIDE the window are ignored; INSIDE fail the day', () => {
  // temp=100 at indices 0-8 is outside day-0 window [9,17) -> day 0 still perfect.
  const outside = evaluateAll(makeHours(48, (i) => (i <= 8 ? { temp: 100 } : {})), [MIDDAY])[0];
  assert.equal(outside.days[0].rating, 'perfect');
  // temp=100 at indices 9-16 IS the day-0 window -> day 0 is null, day 1 unaffected.
  const inside = evaluateAll(makeHours(48, (i) => (i >= 9 && i <= 16 ? { temp: 100 } : {})), [MIDDAY])[0];
  // All 8 of day-0's window hours fail the REQUIRED temp. MIDDAY thresholds a
  // single metric, so the hour is mean(0) = 0 under the amended rule too ->
  // day mean 0 -> clamp 1 (unchanged by the ADR-0011 amendment).
  assert.deepStrictEqual(inside.days[0], { dayIndex: 0, rating: null, score: 1 });
  assert.equal(inside.days[1].rating, 'perfect');
});

// Wrapped window stitches one local-midnight crossing per night; dayIndex is the
// EVENING's calendar day, and startIndex/endIndex are global across the boundary.
test('wrapped window stitches a night across midnight (clean fixture, global indices)', () => {
  const [r] = evaluateAll(makeHours(72), [NIGHT]);
  assert.equal(r.days.length, 3);
  // score: temp 25 in [5,35] -> centre 20, half-width 15 -> 100*(1-5/15) = 200/3;
  // cloudCover 10 inside one-sided max 30 -> 100. Hour mean = (200/3 + 100)/2 =
  // 250/3 = 83.33...; every hour is identical, so the day mean rounds to 83.
  // night 0 = day0 22:00,23:00 (idx 22,23) + day1 00:00,01:00 (idx 24,25)
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 22, endIndex: 26, duration: 4, score: 83 });
  assert.deepStrictEqual(r.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 46, endIndex: 50, duration: 4, score: 83 });
  // tail night: day2 evening only (no day3 morning in the horizon) -> 2 hours
  assert.deepStrictEqual(r.days[2], { dayIndex: 2, rating: 'perfect', startIndex: 70, endIndex: 72, duration: 2, score: 83 });
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
  assert.deepStrictEqual(nocturnal.days[2], { dayIndex: 2, rating: 'perfect', startIndex: 54, endIndex: 58, duration: 4, score: 83 });
});

// Orphan morning: day-0 early hours whose evening is pre-horizon belong to no night
// and are DROPPED (not a separate day-0 window). Start 01:00 local -> idx 0 = 01:00.
test('orphan morning (pre-horizon evening) is dropped, not made its own night', () => {
  const hours = makeHoursAt('2026-06-19T21:00:00Z', 48); // 01:00 local start
  const [r] = evaluateAll(hours, [NIGHT]);
  // idx 0 is 01:00 (< endHour 2) but its evening is before the horizon -> dropped.
  // night 0's evening is day0 22:00,23:00 = idx 21,22; morning day1 00:00,01:00 = idx 23,24.
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 21, endIndex: 25, duration: 4, score: 83 });
});

// A night with no qualifying hours keeps its dense slot as a null day.
test('a non-qualifying night keeps its slot with rating null', () => {
  // Fail cloudCover only during night 0's hours (idx 22-25).
  const hours = makeHours(72, (i) => (i >= 22 && i <= 25 ? { cloudCover: 90 } : {}));
  const [r] = evaluateAll(hours, [NIGHT]);
  // cloudCover is REQUIRED, so all 4 of night 0's hours are Bad -> rating null.
  // Score (amended ADR-0011: the required miss scores 0 for cloudCover only):
  // temp 25 in [5,35] -> 100*(1-5/15) = 200/3; cloudCover 90 -> 0. Hour =
  // (200/3 + 0)/2 = 100/3 = 33.33...; all 4 identical -> 33 (was 1).
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: null, score: 33 });
  assert.equal(r.days[1].rating, 'perfect');
});

// ───────────────────────────── day score (ADR-0011) ─────────────────────────────
// The score is computed from the SAME bucket slices the rating is: window-filtered
// for a same-day window, night-stitched for a wrapped one. Expectations below are
// hand-derived from the ADR formula; the shared worked-example table (and the
// formula itself) is pinned in tests/decision/score.test.js.

test('score is present on every day of every activity, as null or an integer 1..100', () => {
  const hours = makeHours(72, (i) => (i % 7 === 0 ? { temp: 100, dustAlert: true } : {}));
  const results = evaluateAll(hours, [VOLLEYBALL, SHADE, MIDDAY, NIGHT]);
  for (const r of results) {
    for (const day of r.days) {
      assert.ok('score' in day, `${r.activityId} day ${day.dayIndex} must carry score`);
      assert.ok(day.score === null || (Number.isInteger(day.score) && day.score >= 1 && day.score <= 100),
        `${r.activityId} day ${day.dayIndex}: expected null or 1..100, got ${day.score}`);
    }
  }
});

// Key order is the wire contract (ADR-0011): score comes LAST, after the window
// triplet on a rated day and after `rating` on a null one.
test('score is the last key on both a rated and a rating-null day', () => {
  const hours = makeHours(48, (i) => (i < 24 ? { dustAlert: true } : {}));
  const [vb] = evaluateAll(hours, [VOLLEYBALL]);
  assert.deepStrictEqual(Object.keys(vb.days[0]), ['dayIndex', 'rating', 'score']);
  assert.deepStrictEqual(Object.keys(vb.days[1]), ['dayIndex', 'rating', 'startIndex', 'endIndex', 'duration', 'score']);
});

// A "good" day sits between: the optional breach costs its metric's share only.
test('an optional breach degrades the score smoothly where the rating only snaps to good', () => {
  const [vb] = evaluateAll(makeHours(48, () => ({ windSpeed: 20 })), [VOLLEYBALL]);
  // temp 25 -> 100 (centre), windSpeed 20 > max 15 -> 0, dustAlert false -> 100.
  // Hour mean = (100 + 0 + 100)/3 = 200/3 = 66.66... -> day score 67.
  assert.equal(vb.days[0].rating, 'good');
  assert.equal(vb.days[0].score, 67);
  assert.equal(vb.days[1].score, 67);
});

// The nocturnal case the spec asks for, with DIFFERENT values either side of
// midnight: only the stitched 4-hour slice produces 92. The night-stitch
// tripwire — the two ways of getting the slice wrong both read something else:
// the whole calendar day 0 (24 hours) would read 85, and the evening pair alone
// would read 100.
test('a nocturnal bucket scores its night-stitched hours, not its calendar day', () => {
  // night 0 = day0 22:00,23:00 (idx 22,23) + day1 00:00,01:00 (idx 24,25).
  const hours = makeHours(72, (i) => (i === 22 || i === 23 ? { temp: 20 } : {}));
  const [r] = evaluateAll(hours, [NIGHT]);
  // evening: temp 20 = centre of [5,35] -> 100, cloudCover 100 -> hour 100 (x2)
  // morning: temp 25 -> 200/3, cloudCover 100 -> hour 250/3 = 83.33... (x2)
  // day mean = (100 + 100 + 250/3 + 250/3)/4 = (200 + 500/3)/4 = 91.66... -> 92
  assert.equal(r.days[0].score, 92);
  assert.equal(r.days[1].score, 83, 'the next night is untouched');
});

// The score averages the BUCKET's window hours — NOT the rated window's hours.
// Mixed day: 16 in-band hours then 8 out-of-band, so the three candidate slices
// give three different numbers and only the bucket is right. This also pins that
// hour scores are NOT rounded before the day mean (fractional 200/3 hours).
const WIDE = {
  id: 'wide', label: 'Wide Band',
  displayMetrics: ['temp'],
  thresholds: { temp: { min: 5, max: 35, required: true } }, // centre 20, half-width 15
};
test('the score averages the whole bucket, not just the rated window', () => {
  const hours = makeHours(24, (i) => (i >= 16 ? { temp: 100 } : {}));
  const [r] = evaluateAll(hours, [WIDE]);
  // idx 0-15: temp 25 -> 100*(1-5/15) = 200/3 = 66.66... and the hour is Perfect
  // idx 16-23: temp 100 fails the REQUIRED band -> metric 0; WIDE thresholds a
  // single metric, so the hour is mean(0) = 0 (same under the amended ADR-0011
  // rule) and the hour is Bad
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 0, endIndex: 16, duration: 16, score: 44 });
  // Why 44, and what the wrong slices would give:
  //   bucket (all 24h):        (16 x 200/3 + 8 x 0)/24 = 3200/72 = 44.44... -> 44  <- correct
  //   rated window (16h only):  200/3 = 66.66...                             -> 67
  //   hour scores pre-rounded: (16 x 67 + 8 x 0)/24     = 1072/24 = 44.66... -> 45
});

test('a nocturnal bucket also averages its whole stitched night, not its rated window', () => {
  // night 0 = idx 22,23 (evening) + 24,25 (morning); fail cloudCover on idx 25 only.
  // FIXTURE CHANGED for the ADR-0011 amendment (2026-10-01): idx 25 now also
  // carries temp 17. With the old temp 25 the amended hour would be
  // (200/3 + 0)/2 = 33.33..., making the bucket (250 + 100/3)/4 = 70.83... -> 71
  // and the pre-rounded slice (249 + 33)/4 = 70.5 -> 71 — the pre-rounding
  // tripwire would collapse onto the right answer. temp 17 keeps all three
  // candidates distinct (and keeps a genuine half-up tie).
  const hours = makeHours(72, (i) => (i === 25 ? { cloudCover: 90, temp: 17 } : {}));
  const [r] = evaluateAll(hours, [NIGHT]);
  // idx 22,23,24: temp 25 -> 200/3, cloudCover 10 -> 100; hour = 250/3 = 83.33...
  // idx 25: cloudCover 90 fails the REQUIRED max 30 -> 0 for cloudCover only (the
  //   hour is Bad, but under the amended rule it still averages); temp 17 ->
  //   100*(1-|17-20|/15) = 100*(1-3/15) = 80; hour = (80 + 0)/2 = 40
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: 'perfect', startIndex: 22, endIndex: 25, duration: 3, score: 73 });
  //   bucket (all 4h):         (3 x 250/3 + 40)/4 = 290/4 = 72.5 -> half-up -> 73  <- correct
  //   rated window (3h only):   250/3 = 83.33...                              -> 83
  //   hour scores pre-rounded: (3 x 83 + 40)/4     = 289/4 = 72.25            -> 72
  //   (was 63 / 83 / 62 under the retired zero-the-hour rule with temp 25)
});

// The NULL RULE, and the only way a zero-hour bucket arises in evaluateAll: a
// same-day window that no hour of a calendar day falls inside. Local start is
// 18:00, so day 0 holds only 18:00-23:00 and the [9,17) window is already past.
// (bucketNightWindow's `|| { hours: [] }` gap fallback is defensive — contiguous
// hours cannot skip a night ordinal — so this filter is the reachable branch.)
test('score is null IFF the bucket has zero window hours (day-0 window already past)', () => {
  const hours = makeHoursAt('2026-06-19T14:00:00Z', 30); // 18:00 local start
  const [r] = evaluateAll(hours, [MIDDAY]);
  assert.equal(r.days.length, 2);
  assert.deepStrictEqual(r.days[0], { dayIndex: 0, rating: null, score: null },
    'no hour of day 0 is in [9,17) -> an empty bucket -> null, NOT the clamped 1');
  // day 1 is a full calendar day: idx 6 = 00:00, so the window is idx 15..22.
  assert.deepStrictEqual(r.days[1], { dayIndex: 1, rating: 'perfect', startIndex: 15, endIndex: 23, duration: 8, score: 100 });
});

// Independence rule (ADR-0011): the score is derived beside the verdict and can
// never move it. A fixture whose score changes while every rating holds steady.
test('the score never feeds the rating', () => {
  const centred = evaluateAll(makeHours(48), [SHADE])[0];           // temp 25, centre of [15,35]
  const offCentre = evaluateAll(makeHours(48, () => ({ temp: 34 })), [SHADE])[0]; // still inside the band
  assert.equal(centred.days[0].score, 100);
  assert.equal(offCentre.days[0].score, 10); // 100*(1-|34-25|/10) = 10
  assert.equal(centred.days[0].rating, 'perfect');
  assert.equal(offCentre.days[0].rating, 'perfect', 'a near-edge score must not downgrade the verdict');
});
