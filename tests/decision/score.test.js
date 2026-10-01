const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { metricScore, hourScore, dayScore } = require("../../src/decision/score");

// The ADR-0011 worked examples live in tests/fixtures/day-score-examples.json
// (the clock-labels.json mold, ADR-0007). The iOS score mirror that once
// transcribed the same table was deleted 2026-10-01 (ADR-0007 mirror #4), so
// this suite alone reads it now. Every expectation below comes from that file's
// hand-derived `expected` values; nothing here recomputes them, so a formula
// drift shows up as a failure rather than as a self-agreeing table.
const dayScoreExamples = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../fixtures/day-score-examples.json"), "utf8"),
);

test("fixture table shape pin (every case named, expected, derived)", () => {
  for (const group of ["metricCases", "hourCases", "dayCases"]) {
    assert.ok(Array.isArray(dayScoreExamples[group]) && dayScoreExamples[group].length > 0);
    for (const c of dayScoreExamples[group]) {
      assert.ok(typeof c.name === "string" && c.name.length > 0, "every case is named");
      assert.ok("expected" in c, `${c.name} carries a hand-computed expected value`);
      assert.ok(typeof c.derivation === "string" && c.derivation.length > 0,
        `${c.name} carries its one-line arithmetic`);
    }
  }
});

// --- per-metric depth-in-band ---
for (const c of dayScoreExamples.metricCases) {
  test(`metricScore: ${c.name} -> ${c.expected} (${c.derivation})`, () => {
    // Floating point: 100*(1-7/10) is not exactly 30 in binary, so compare at
    // a tolerance the day-level rounding can never notice.
    const actual = metricScore(c.value, c.threshold);
    assert.ok(Math.abs(actual - c.expected) < 1e-9,
      `expected ${c.expected}, got ${actual}`);
  });
}

// --- per-hour mean over thresholded metrics ---
for (const c of dayScoreExamples.hourCases) {
  test(`hourScore: ${c.name} -> ${c.expected} (${c.derivation})`, () => {
    const actual = hourScore(c.hourValues, c.thresholds);
    assert.ok(Math.abs(actual - c.expected) < 1e-9,
      `expected ${c.expected}, got ${actual}`);
  });
}

// displayMetrics is not even a parameter of hourScore — the exclusion is
// structural, but pin it against the fixture case that documents it.
test("hourScore ignores display-only metrics entirely (no judging what isn't thresholded)", () => {
  const c = dayScoreExamples.hourCases.find((x) => x.name === "display-only-metric-excluded");
  assert.ok(c.displayMetrics.includes("humidity") && !("humidity" in c.thresholds));
  // A wildly out-of-range humidity cannot move the score: it is display-only.
  assert.equal(hourScore({ ...c.hourValues, humidity: -999 }, c.thresholds), c.expected);
});

// ADR-0011 amendment (2026-10-01): a required miss scores 0 for THAT metric
// only — the hour is not zeroed. Pinned outside the fixture too, so a revert to
// the original "required miss zeroes the hour" rule fails with a named test.
test("hourScore: a required miss plus a passing optional metric scores the mean, not 0", () => {
  const thresholds = {
    temp: { min: 10, max: 30, required: true },       // 40 > max 30 -> 0 (required miss)
    dustAlert: { type: "flag", forbidTrue: true, required: false }, // false -> 100
  };
  // mean(0, 100) = 50 — the pre-amendment rule would have returned 0.
  assert.strictEqual(hourScore({ temp: 40, dustAlert: false }, thresholds), 50);
  // A Bad hour still carries a gradient at the day level: two such hours ->
  // mean(50, 50) = 50 -> 50, never the floor 1.
  assert.strictEqual(dayScore([{ temp: 40, dustAlert: false }, { temp: 40, dustAlert: false }], thresholds), 50);
});

// --- per-day mean -> round -> clamp 1..100, null on an empty window ---
// dayCases supply precomputed hour scores, so drive dayScore through an
// hour-shaped stub: one thresholded metric whose depth IS the given hour score.
// temp band [0,200] has centre 100 and half-width 100, so metricScore(v) =
// 100*(1-|v-100|/100) = v for any v in 0..100 — the identity we need.
const IDENTITY_THRESHOLDS = { temp: { min: 0, max: 200, required: false } };
for (const c of dayScoreExamples.dayCases) {
  test(`dayScore: ${c.name} -> ${c.expected} (${c.derivation})`, () => {
    const hours = c.hourScores.map((s) => ({ temp: s }));
    assert.strictEqual(dayScore(hours, IDENTITY_THRESHOLDS), c.expected);
  });
}

test("the identity stub really is an identity (guards the dayCases harness)", () => {
  for (const v of [0, 1, 10, 11, 50, 62.5, 75, 83.33333333333333, 100]) {
    assert.ok(Math.abs(metricScore(v, IDENTITY_THRESHOLDS.temp) - v) < 1e-9);
  }
});

// --- NaN firewall: every reachable path yields null or an integer in 1..100 ---
// thresholds:{} validates (a show-but-don't-judge activity), and so does a
// zero-width band {min:20,max:20} — both would divide by zero if unhandled and
// JSON.stringify would emit the NaN as `null`, silently breaking the ADR's
// "null IFF zero window hours" rule.
test("score is never NaN: empty thresholds and a zero-width band stay in range", () => {
  const cases = [
    { thresholds: {}, hour: { temp: 20 } },
    { thresholds: { temp: { min: 20, max: 20, required: false } }, hour: { temp: 20 } },
    { thresholds: { temp: { min: 20, max: 20, required: false } }, hour: { temp: 99 } },
    { thresholds: { temp: { min: 20, max: 20, required: true } }, hour: { temp: 99 } },
  ];
  for (const { thresholds, hour } of cases) {
    const s = dayScore([hour, hour], thresholds);
    assert.ok(Number.isInteger(s) && s >= 1 && s <= 100,
      `expected an integer 1..100, got ${s} for ${JSON.stringify(thresholds)}`);
  }
});

// checkThreshold returns TRUE for NaN (both NaN < min and NaN > max are false),
// so a NaN metric value reaches the mean and a NaN score would serialize as
// `null` — falsely claiming an empty bucket. Unreachable through the wire (JSON
// cannot encode NaN, and the validators force finite bounds), but the guard
// makes "null iff zero window hours" structural instead of circumstantial.
test("a NaN metric value scores the floor, never a NaN that serializes as null", () => {
  const required = { temp: { min: 10, max: 30, required: true } };
  const optional = { temp: { min: 10, max: 30, required: false } };

  for (const thresholds of [required, optional]) {
    const s = dayScore([{ temp: NaN }, { temp: 20 }], thresholds);
    assert.strictEqual(s, 1, 'garbage data fails to the floor, like absent data under B2');
    assert.strictEqual(JSON.stringify({ score: s }), '{"score":1}', 'and never serializes as null');
  }

  // The hour-level value is the NaN itself — the guard lives in dayScore, which
  // is the only path onto the wire. Pin that so the guard cannot move upward
  // unnoticed and change hourScore's contract.
  assert.ok(Number.isNaN(hourScore({ temp: NaN }, required)));
});

test("a zero-hour bucket is the ONLY null — an all-zero day clamps to 1 instead", () => {
  // Single required metric failing every hour: each hour is mean(0) = 0, so the
  // day mean is 0 -> clamped to 1. (With a second, passing metric the day would
  // NOT be 1 — see the amended required-miss pin above.)
  const required = { temp: { min: 10, max: 30, required: true } };
  assert.strictEqual(dayScore([], required), null);
  assert.strictEqual(dayScore([{ temp: 99 }, { temp: 99 }], required), 1);
});
