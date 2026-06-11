const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluateAll } = require("../../src/decision/evaluateAll");

function makeHours(overrides = {}) {
  return Array.from({ length: 24 }, (_, i) => ({
    hour:         i,
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
  }));
}

test("evaluateAll returns one result per activity", () => {
  const results = evaluateAll(makeHours());
  assert.ok(Array.isArray(results));
  assert.equal(results.length, 5); // boat-fishing-pro, boat-fishing-lite, shore-fishing, stargazing-lite, volleyball
});

test("every result has required shape fields", () => {
  const results = evaluateAll(makeHours());
  for (const result of results) {
    assert.ok("activityId" in result,     `missing activityId on ${result.label}`);
    assert.ok("label" in result,          `missing label on ${result.activityId}`);
    assert.ok("rating" in result,         `missing rating on ${result.activityId}`);
    assert.ok("displayMetrics" in result, `missing displayMetrics on ${result.activityId}`);
  }
});

test("activity IDs are stable kebab-case strings", () => {
  const results = evaluateAll(makeHours());
  const ids = results.map((r) => r.activityId);
  assert.ok(ids.includes("volleyball"));
  assert.ok(ids.includes("boat-fishing-pro"));
  assert.ok(ids.includes("boat-fishing-lite"));
  assert.ok(ids.includes("shore-fishing"));
  assert.ok(ids.includes("stargazing-lite"));
});

test("dustAlert true triggers bad rating for volleyball", () => {
  const results = evaluateAll(makeHours({ dustAlert: true }));
  const vb = results.find((r) => r.activityId === "volleyball");
  assert.equal(vb.rating, null);
});

// E1 — seaWarning flag fails all three fishing activities (parallel to dustAlert for volleyball)
test("seaWarning true triggers null rating for all fishing activities (E1)", () => {
  const results = evaluateAll(makeHours({ seaWarning: true }));
  const fishingIds = ["boat-fishing-pro", "boat-fishing-lite", "shore-fishing"];
  for (const id of fishingIds) {
    const a = results.find((r) => r.activityId === id);
    assert.equal(a.rating, null, `${id} should have null rating when seaWarning is true`);
  }
});

// E2 — exceeding an OPTIONAL threshold downgrades volleyball from "perfect" to "good"
test('"good" rating path: optional windSpeed exceeded for volleyball (E2)', () => {
  // volleyball windSpeed threshold: { max: 15, required: false } — exceeding it should be "good", not null
  const results = evaluateAll(makeHours({ windSpeed: 20 }));
  const vb = results.find((r) => r.activityId === "volleyball");
  assert.equal(vb.rating, "good");
  assert.equal(typeof vb.startIndex, "number");
  assert.equal(typeof vb.endIndex, "number");
  assert.equal(typeof vb.duration, "number");
  assert.equal(vb.startIndex, 0);
  assert.equal(vb.endIndex, 24);
  assert.equal(vb.duration, 24);
});

// E3 — when rating is null, the window fields must be ABSENT (not present as undefined)
test("null-rating activities have no startIndex/endIndex/duration keys (E3)", () => {
  // Extreme temp fails required temp threshold for every activity
  const results = evaluateAll(makeHours({ temp: 100 }));
  const nullRated = results.filter((r) => r.rating === null);
  assert.ok(nullRated.length > 0, "expected at least one null-rated activity");
  for (const r of nullRated) {
    assert.equal("startIndex" in r, false, `startIndex should be absent on ${r.activityId}`);
    assert.equal("endIndex"   in r, false, `endIndex should be absent on ${r.activityId}`);
    assert.equal("duration"   in r, false, `duration should be absent on ${r.activityId}`);
  }
});
