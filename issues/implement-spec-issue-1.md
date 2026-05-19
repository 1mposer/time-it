# Implementation spec — Issue #1: Window-evaluation wraps around midnight

> GitHub issue: https://github.com/1mposer/time-it/issues/1
> Branch: `fix/issue-1-window-crossover`
> Domain glossary: [`CONTEXT.md`](../CONTEXT.md)

This spec is self-contained. The next agent should not need any other conversation context to complete the task.

---

## 1. Context (the bug)

`evaluate()` in `src/decision/decision_engine.js` returns nonsensical-looking output when the best forecast **Window** crosses midnight — e.g. `{startHour: 15, endHour: 14}` for a 24-hour run.

**Root cause:** `findLongestRun` uses the clock hour (`ratedHour.hour`, 0–23) as `start`/`end` of the run. Clock hours wrap at midnight, so a monotonic chronological scan produces non-monotonic `start`/`end` values with no day context to disambiguate.

**Fix shape:** The forecast is always 24 chronological entries starting at "now" (`parse.js:5` slices to 24, populated in real-time order). Array index is a clean, monotonic position the algorithm can use internally. Clock-hour labels are dropped from the engine output entirely — they belong to a later UI-contract phase (along with `forecastStart` for timezone-aware rendering).

This PR also stabilises the JSON contract the engine emits, since the iOS app will eventually consume it.

---

## 2. Decisions already made (do not relitigate)

### 2.1 Output contract

`evaluate()` returns one of:

```js
// success
{ rating: "perfect" | "good", activityId, startIndex, endIndex, duration }

// no qualifying window
{ rating: null, activityId }
```

- `startIndex` — inclusive, 0–23, array position in the 24-hour forecast.
- `endIndex` — exclusive, 1–24. `startIndex < endIndex` always.
- `duration` — `endIndex - startIndex`. Kept as a first-class field even though derivable, because it's the algorithm's primary output and supports user-side **Session**-fit logic (see `CONTEXT.md`).
- `activityId` — passed through from `userPrefs` so the payload is self-describing.

### 2.2 No clock-hour labels in the engine output

`startHour` / `endHour` were considered and rejected for this PR. Reasons:

1. The forecast hour is parsed from UTC ISO strings (`meteosource.js:4`, `index.js:21` passes `timezone: "UTC"`). For a UAE user, `hour: 15` means 19:00 local — these are not display-ready labels.
2. The iOS app needs `forecastStart` (a UTC anchor) and a timezone to render correctly. Both are deferred to the UI-contract phase. Adding UTC-hour labels now would lock in a misleading contract.
3. `startIndex` / `endIndex` are timezone-agnostic and unambiguously correct ("N hours from the start of the forecast").

### 2.3 Engine owns the null shape

`evaluate()` builds the full JSON shape for *both* success and null cases. `index.js` becomes a pure passthrough that just stringifies the result. Reason: `evaluate()` already receives `userPrefs.activityId`, so it has everything needed for the null case — having `index.js` re-assemble that shape would be redundant and a future source of drift.

### 2.4 Rename `findLongestRun` → `findLongestWindow`

The canonical domain term is **Window** (see `CONTEXT.md`). "Run" was internal algorithm slang that didn't match the rest of the vocabulary. Rename happens in this PR.

### 2.5 Internal ratings structure: flat string array

`evaluate()` builds `ratings = hours.map(h => evaluateHour(h, userPrefs.thresholds))` — a flat array of `"perfect" | "good" | "bad"` strings. `findLongestWindow(ratings, targetRating)` walks this array. No `{hour, rating}` wrapper objects — the `hour` field would be dead weight now that clock labels are dropped.

### 2.6 Tests in this PR

`node:test` (no new dependencies). Add `"test": "node --test"` to `package.json` scripts. New test file at `tests/decision/decision_engine.test.js`.

---

## 3. Out of scope

- **iOS UI / notification rendering** — locked behind the UI-contract phase.
- **`forecastStart` / `generatedAt` timestamps in the payload** — deferred to the UI-contract phase. `startIndex` covers the "hours from now" need for the iOS app's local-reminder math in the meantime.
- **Multi-activity evaluation, APNs delivery, scheduling** — separate work.
- **`activityId` casing convention** (`"volleyball"` vs `"volleyBall"`) — tracked in [issue #2](https://github.com/1mposer/time-it/issues/2). Pass `activityId` through as-is; do not normalize.

---

## 4. Changes

### 4.1 `src/decision/decision_engine.js`

Replace lines 25–57 (the current `findLongestRun` and `evaluate`) with the structure below. Keep `checkThreshold` and `evaluateHour` (lines 1–23) unchanged.

```js
function findLongestWindow(ratings, targetRating) {
  let best = null;
  let current = null;

  for (let i = 0; i < ratings.length; i++) {
    if (ratings[i] === targetRating) {
      if (!current) current = { startIndex: i, endIndex: i + 1, duration: 1 };
      else {
        current.endIndex = i + 1;
        current.duration++;
      }
    } else {
      if (current && (!best || current.duration > best.duration)) best = current;
      current = null;
    }
  }
  if (current && (!best || current.duration > best.duration)) best = current;

  return best;
}

function evaluate(hours, userPrefs) {
  const ratings = hours.map((h) => evaluateHour(h, userPrefs.thresholds));

  const perfectWindow = findLongestWindow(ratings, "perfect");
  if (perfectWindow) {
    return { rating: "perfect", activityId: userPrefs.activityId, ...perfectWindow };
  }

  const goodWindow = findLongestWindow(ratings, "good");
  if (goodWindow) {
    return { rating: "good", activityId: userPrefs.activityId, ...goodWindow };
  }

  return { rating: null, activityId: userPrefs.activityId };
}

module.exports = { evaluate };
```

Notes:
- Preserve the perfect-before-good preference order.
- `findLongestWindow` returns `null` internally when no run is found; `evaluate()` translates that into the structured null shape.

### 4.2 `index.js`

Replace line 32:

```js
// before
console.log("Best window for", sampleUserPrefs.activityId, ":", window);

// after
console.log(JSON.stringify(window, null, 2));
```

No other changes to `index.js`. Do not wrap or post-process the engine's return.

### 4.3 `package.json`

Add a `test` script:

```json
"scripts": {
  "start": "node index.js",
  "test": "node --test"
}
```

### 4.4 `tests/decision/decision_engine.test.js` (new file)

Use `node:test` and `node:assert/strict`. Test cases below — each is a separate `test()` block.

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluate } = require("../../src/decision/decision_engine");

const prefs = {
  activityId: "volleyball",
  thresholds: {
    temp:     { min: 15, max: 35, required: true },
    humidity: { max: 60,          required: true },
  },
};

// helper: build a 24-hour forecast where every hour is Perfect
function perfectHours(startClockHour) {
  return Array.from({ length: 24 }, (_, i) => ({
    hour:     (startClockHour + i) % 24,
    temp:     25,
    humidity: 40,
  }));
}

// helper: build a forecast from an array of {pass} flags
function hoursFromPasses(passes) {
  return passes.map((pass, i) => ({
    hour:     i,
    temp:     pass ? 25 : 100,   // fail required temp threshold when !pass
    humidity: 40,
  }));
}

test("midnight-crossing 24-hour Perfect window", () => {
  const result = evaluate(perfectHours(15), prefs);
  assert.deepEqual(result, {
    rating: "perfect",
    activityId: "volleyball",
    startIndex: 0,
    endIndex: 24,
    duration: 24,
  });
});

test("single-hour Perfect window surrounded by Bad", () => {
  const passes = Array(24).fill(false);
  passes[5] = true;
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.startIndex, 5);
  assert.equal(result.endIndex, 6);
  assert.equal(result.duration, 1);
});

test("no qualifying hours returns null-rating shape", () => {
  const passes = Array(24).fill(false);
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.deepEqual(result, { rating: null, activityId: "volleyball" });
});

test("Perfect window preferred over longer Good window", () => {
  // 2 Perfect hours, then 5 Good hours (humidity high but not required-failing)
  // Configure thresholds so humidity is non-required
  const localPrefs = {
    activityId: "volleyball",
    thresholds: {
      temp:     { min: 15, max: 35, required: true },
      humidity: { max: 60,          required: false },
    },
  };
  const hours = [
    { hour: 0, temp: 25, humidity: 40 }, // perfect
    { hour: 1, temp: 25, humidity: 40 }, // perfect
    { hour: 2, temp: 25, humidity: 90 }, // good (humidity fails, but not required)
    { hour: 3, temp: 25, humidity: 90 }, // good
    { hour: 4, temp: 25, humidity: 90 }, // good
    { hour: 5, temp: 25, humidity: 90 }, // good
    { hour: 6, temp: 25, humidity: 90 }, // good
  ];
  // pad to 24
  while (hours.length < 24) hours.push({ hour: hours.length, temp: 100, humidity: 40 });
  const result = evaluate(hours, localPrefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.duration, 2);
});

test("Perfect run ending at the last array element is captured", () => {
  const passes = Array(24).fill(false);
  passes[22] = true;
  passes[23] = true;
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.startIndex, 22);
  assert.equal(result.endIndex, 24);
  assert.equal(result.duration, 2);
});
```

---

## 5. Acceptance criteria

- [ ] `npm test` passes — all five test cases above succeed.
- [ ] `npm start` runs against the live API and prints valid JSON (`JSON.parse` of the output succeeds) with the expected fields: `rating`, `activityId`, and either (`startIndex`, `endIndex`, `duration`) or nothing else when `rating: null`.
- [ ] `findLongestRun` is gone; only `findLongestWindow` exists. `grep -r "findLongestRun" src/ tests/` returns nothing.
- [ ] `startHour` / `endHour` are gone from the engine output. `grep -r "startHour\|endHour" src/ tests/` returns nothing.
- [ ] `index.js:32` is a single `console.log(JSON.stringify(...))` line; no string concatenation, no post-processing of the engine return.

---

## 6. Related artifacts

- [`CONTEXT.md`](../CONTEXT.md) — domain glossary. Use the canonical terms (**Window**, **Rating**, **Threshold**, etc.) in any new comments or commit messages.
- [Issue #1](https://github.com/1mposer/time-it/issues/1) — the bug report this PR closes.
- [Issue #2](https://github.com/1mposer/time-it/issues/2) — `activityId` casing convention (deferred).
