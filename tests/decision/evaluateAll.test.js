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

function baseHour(overrides = {}) {
  return {
    temp:         25,
    humidity:     40,
    windSpeed:    10,
    rainFall:     0,
    cloudCover:   10,
    visibility:   10,
    moon:         [],
    uV:           3,
    dustAlert:    false,
    darkness:     0,
    douglasScale: 0,
    swellHeight:  0,
    swellLength:  0,
    tide:         0,
    seaWarning:   false,
    ...overrides,
  };
}

// `perIndex(i)` may return per-hour overrides; hours are then tagged with their
// forecast-location localDay exactly as the real pipeline does before evaluateAll.
function makeHours(count, perIndex = () => ({})) {
  const hours = Array.from({ length: count }, (_, i) => baseHour(perIndex(i)));
  return tagLocalDays(hours, FORECAST_START, TIMEZONE);
}

test("evaluateAll returns one result per activity", () => {
  const results = evaluateAll(makeHours(48));
  assert.ok(Array.isArray(results));
  assert.equal(results.length, 5); // boat-fishing-pro, boat-fishing-lite, shore-fishing, volleyball, stargazing-lite
});

test("every result carries activityId, label, displayMetrics, days[]", () => {
  const results = evaluateAll(makeHours(48));
  for (const result of results) {
    assert.ok("activityId" in result,     `missing activityId on ${result.label}`);
    assert.ok("label" in result,          `missing label on ${result.activityId}`);
    assert.ok("displayMetrics" in result, `missing displayMetrics on ${result.activityId}`);
    assert.ok(Array.isArray(result.days), `missing days[] on ${result.activityId}`);
    // The singular top-level window is removed (ADR-0004 sub-decision 2).
    assert.equal("rating"     in result, false, `top-level rating must be removed on ${result.activityId}`);
    assert.equal("startIndex" in result, false, `top-level startIndex must be removed on ${result.activityId}`);
  }
});

test("activity IDs are stable kebab-case strings", () => {
  const ids = evaluateAll(makeHours(48)).map((r) => r.activityId);
  assert.ok(ids.includes("volleyball"));
  assert.ok(ids.includes("boat-fishing-pro"));
  assert.ok(ids.includes("boat-fishing-lite"));
  assert.ok(ids.includes("shore-fishing"));
  assert.ok(ids.includes("stargazing-lite"));
});

test("days[] is one dense entry per local calendar day, dayIndex contiguous from 0", () => {
  const results = evaluateAll(makeHours(48));
  for (const result of results) {
    assert.equal(result.days.length, 2, `${result.activityId} should bucket into 2 local days`);
    result.days.forEach((day, i) => {
      assert.equal(day.dayIndex, i, `${result.activityId} days[${i}].dayIndex must equal its position`);
    });
  }
});

// CONSTRAINT (ADR-0004 pin 1): startIndex/endIndex are GLOBAL indices into hours[],
// never day-relative. A window on day >= 1 is the only thing that catches a missing
// per-day offset — day 0's offset is 0 and would pass even if the offset were dropped.
test("per-day window indices are global, not day-relative (offset applied on day >= 1)", () => {
  // All 48 hours perfect for volleyball -> a full-day window on each day.
  const vb = evaluateAll(makeHours(48)).find((r) => r.activityId === "volleyball");

  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: "perfect", startIndex: 0,  endIndex: 24, duration: 24 });
  assert.deepStrictEqual(vb.days[1], { dayIndex: 1, rating: "perfect", startIndex: 24, endIndex: 48, duration: 24 });
});

// A non-qualifying day keeps its slot: { dayIndex, rating: null }, window triplet ABSENT
// (ADR-0004 sub-decision 3). Day 0 fails (dustAlert), day 1 qualifies.
test("null day keeps its slot with the window fields absent", () => {
  const hours = makeHours(48, (i) => (i < 24 ? { dustAlert: true } : {}));
  const vb = evaluateAll(hours).find((r) => r.activityId === "volleyball");

  assert.deepStrictEqual(vb.days[0], { dayIndex: 0, rating: null });
  assert.equal("startIndex" in vb.days[0], false);
  assert.equal("endIndex"   in vb.days[0], false);
  assert.equal("duration"   in vb.days[0], false);
  assert.equal(vb.days[1].rating, "perfect");
  assert.equal(vb.days[1].startIndex, 24);
});

// Optional-threshold breach downgrades perfect -> good (parallels the old E2),
// now asserted per day.
test('"good" path: optional windSpeed exceeded downgrades volleyball per day (E2)', () => {
  const vb = evaluateAll(makeHours(48, () => ({ windSpeed: 20 }))).find((r) => r.activityId === "volleyball");
  assert.equal(vb.days[0].rating, "good");
  assert.equal(vb.days[1].rating, "good");
});

// dustAlert flag fails volleyball on the affected day (parallels the old flag test).
test("dustAlert true yields null rating for volleyball on the affected day", () => {
  const vb = evaluateAll(makeHours(48, () => ({ dustAlert: true }))).find((r) => r.activityId === "volleyball");
  assert.equal(vb.days[0].rating, null);
  assert.equal(vb.days[1].rating, null);
});

// E1 — seaWarning flag fails all three fishing activities on the affected day.
test("seaWarning true yields null rating for all fishing activities per day (E1)", () => {
  const results = evaluateAll(makeHours(48, () => ({ seaWarning: true })));
  for (const id of ["boat-fishing-pro", "boat-fishing-lite", "shore-fishing"]) {
    const a = results.find((r) => r.activityId === id);
    assert.equal(a.days[0].rating, null, `${id} day 0 should be null when seaWarning is true`);
    assert.equal(a.days[1].rating, null, `${id} day 1 should be null when seaWarning is true`);
  }
});
