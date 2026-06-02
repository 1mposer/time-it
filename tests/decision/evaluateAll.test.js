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
