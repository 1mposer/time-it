# Implementation spec — Issue #3: Fix backend internals — activity schemas, forecastStart, multi-activity evaluator

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: nothing — implement this first
> Required by: [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)), [Issue #5a (iOS Core)](../current/implement-spec-issue-5a-ios-core.md)

This spec is self-contained. The implementing agent should not need any other conversation context to complete the task.

---

## 1. Context

The decision engine (`evaluate()`) reads thresholds in the shape `{ metricName: { min?, max?, required } }`, but all three activity files (`volleyBall.js`, `fishing.js`, `starGazing.js`) use a flat naming convention (`tempMax: 35`, `windMax: 15`) that the engine never reads. This means all activity thresholds are **silently ignored** at runtime — `evaluate()` always receives empty threshold objects and every hour passes trivially.

Additionally:
- `parse.js` returns a bare array, but the iOS app (Issue #5) needs a `forecastStart` ISO timestamp alongside the hours so it can map `startIndex: 3` to a real clock time.
- There is no multi-activity evaluator — the system can only evaluate one activity per run.
- `volleyBall` is exported as a single object; `fishing` and `starGazing` as arrays. This inconsistency makes iteration fragile.
- The `activityId` stored in the engine output uses the object variable name (`"volleyBall"`, `"boatFishingPro"`) which is inconsistent casing. Each activity needs a stable `id` field.

This issue fixes all of the above. No HTTP layer, no iOS code — backend internals only.

---

## 2. Decisions already made (do not relitigate)

### 2.1 Canonical threshold schema

The decision engine already reads `config.min`, `config.max`, and `config.required`. All activity files must be rewritten to this shape:

```js
thresholds: {
  temp:      { min: 15, max: 35, required: true  },
  windSpeed: {          max: 15, required: false },
}
```

### 2.2 Boolean flag thresholds (`dustAlert`, `seaWarning`)

These fields are booleans in the parsed hourly data (`true`/`false`). The engine's `checkThreshold` currently uses numeric comparisons only. Add a `type: "flag"` branch:

```js
// add to checkThreshold(), before the existing min/max checks
if (config.type === "flag" && config.forbidTrue && value === true) return false;
```

Activity definitions use: `dustAlert: { forbidTrue: true, type: "flag", required: true }`

Do **not** use `max: false` or `max: 0` as a workaround — they don't work for booleans and produce misleading definitions.

### 2.3 Each activity object needs `id` and `displayMetrics`

`id` — a stable lowercase kebab-case identifier used as `activityId` in the engine output and in API responses. This replaces the current pattern where `index.js` passes a hardcoded string.

`displayMetrics` — an array of metric key names that the iOS dashboard card will display for this activity. The backend decides which metrics are relevant; the iOS app renders whatever the backend says without hardcoding per-activity logic.

### 2.4 All activity exports are arrays

Currently `volleyBall` is a single object, `fishing` and `starGazing` are arrays. Standardize: every activity file exports an array (even if it has one element). This makes `evaluateAll.js` simple — it always iterates without branching.

### 2.5 StargazingPro is deferred

`starGazingPro` requires `atmosTransparency`, `moonPhase` matching, meteor shower calendar, and planet opposition data — none of which are provided by the Meteosource API or implemented anywhere. Do **not** remove the definition, but do **not** include it in the active export array. Keep it in the file as a commented-out constant with a `// DEFERRED: requires astronomy calendar data` note.

### 2.6 Fishing thresholds need realistic values

The current fishing thresholds are all zeros (`tempMin: 0, tempMax: 0`), which means no hour can fail the temp check and the "bad" rating is never triggered by temperature. Replace with realistic values (see Section 4).

### 2.7 `parse.js` returns `{ forecastStart, hours }` not a bare array

`forecastStart` is the ISO 8601 timestamp of the first hourly entry (e.g. `"2026-05-19T15:00:00"`). It is extracted from `row.date` of the first hourly row before the `.map()`. The return shape changes from an array to `{ forecastStart, hours }`. All callers of `parseWeather` must be updated.

### 2.8 `evaluateAll.js` is a new file, not added to the engine

Multi-activity evaluation is an orchestration concern, not part of the core `evaluate()` function. Create `src/decision/evaluateAll.js` as a separate module that imports both the engine and the activities index.

---

## 3. Out of scope

- HTTP server, REST endpoints — covered in Issue #4.
- iOS app — covered in Issue #5.
- `starGazingPro` astronomy features — deferred indefinitely.
- Tide data — `tide` is currently hardcoded to `0` in `parse.js`. Leave it as-is; the `tideMin`/`tideMax` thresholds are also removed from fishing definitions in this issue.
- Adding new activities (Cycling, Hiking, Padel) — separate future issue.
- Tests for `evaluateAll.js` — a minimal smoke test file only (`tests/decision/evaluateAll.test.js`); full activity integration tests are a future issue.

---

## 4. Changes

### 4.1 `src/decision/decision_engine.js`

Add a `type: "flag"` branch to `checkThreshold`. Replace lines 2–6:

```js
function checkThreshold(value, config) {
  if (config.type === "flag" && config.forbidTrue && value === true) return false;
  if (config.min !== undefined && value < config.min) return false;
  if (config.max !== undefined && value > config.max) return false;
  return true;
}
```

No other changes to this file.

### 4.2 `src/activities/volleyBall.js`

Complete replacement:

```js
const volleyBall = [
  {
    id: "volleyball",
    label: "Volleyball",
    displayMetrics: ["temp", "windSpeed", "humidity", "uV"],
    thresholds: {
      temp:      { min: 15, max: 35, required: true  },
      humidity:  {          max: 60, required: true  },
      windSpeed: {          max: 15, required: false },
      uV:        {          max: 6,  required: false },
      dustAlert: { forbidTrue: true, type: "flag", required: true },
    },
  },
];

module.exports = { volleyBall };
```

### 4.3 `src/activities/fishing.js`

Complete replacement:

```js
const boatFishingPro = {
  id: "boat-fishing-pro",
  label: "Boat Fishing Pro",
  displayMetrics: ["temp"],
  thresholds: {
    temp:         { min: 10, max: 40,  required: true  },
    douglasScale: {          max: 3,   required: true  },  // 0=calm 3=slight 5=rough 9=phenomenal
    swellHeight:  {          max: 2.5, required: true  },  // metres; >4m = heavy swell
    swellLength:  {          max: 200, required: false },  // metres
    seaWarning:   { forbidTrue: true, type: "flag", required: true },
  },
};

const boatFishingLite = {
  id: "boat-fishing-lite",
  label: "Boat Fishing Lite",
  displayMetrics: ["temp", "windSpeed"],
  thresholds: {
    temp:         { min: 10, max: 40, required: true  },
    windSpeed:    {          max: 25, required: true  },
    seaWarning:   { forbidTrue: true, type: "flag", required: true },
  },
};

const shoreFishing = {
  id: "shore-fishing",
  label: "Shore Fishing",
  displayMetrics: ["temp", "windSpeed"],
  thresholds: {
    temp:         { min: 15, max: 38, required: true  },
    windSpeed:    {          max: 20, required: false },
    douglasScale: {          max: 4,  required: false },
    seaWarning:   { forbidTrue: true, type: "flag", required: true },
  },
};

const fishing = [boatFishingPro, boatFishingLite, shoreFishing];

module.exports = { fishing };
```

Note: `tide` thresholds are removed because `parse.js` hardcodes `tide: 0` and there is no real data source. `tideMin`/`tideMax` would match trivially (0 always passes) and are misleading.

### 4.4 `src/activities/starGazing.js`

Complete replacement. Pro is kept as a commented-out constant (do not delete domain knowledge):

```js
// DEFERRED: starGazingPro requires atmosTransparency, moon phase matching,
// meteor shower calendar, and planet opposition data. None of these are
// provided by Meteosource. Implement when an astronomy data source is integrated.
//
// const starGazingPro = {
//   id: "stargazing-pro",
//   label: "Stargazing Pro",
//   thresholds: {
//     temp:               { min: 5, max: 30, required: true  },
//     cloudCover:         { max: 20,          required: true  },
//     atmosTransparency:  { min: 3, max: 7,   required: false },  // NELM scale 0-7
//     moonPhase:          ["third quarter", "first quarter"],     // calendar lookup needed
//     specialSky:         ["quadrantids", "lyrids", ...],        // calendar lookup needed
//     planetOppositions:  ["jupiter", "mars", ...],              // calendar lookup needed
//   },
// };

// DEFERRED: totalSolarEclipse was in the original starGazingLite thresholds but removed.
// The engine's flag type only supports forbidTrue (penalise when an alert is present).
// A solar eclipse is an event you want to be present — "require true" — which the engine
// cannot currently express. Tracked in Issue #8 (implement-spec-issue-8-require-true-threshold.md).

const starGazingLite = {
  id: "stargazing-lite",
  label: "Stargazing Lite",
  displayMetrics: ["temp", "cloudCover"],
  thresholds: {
    temp:       { min: 5, max: 30, required: true  },
    cloudCover: {         max: 20, required: true  },  // % cloud cover; must be near-clear
    darkness:   { max: 4,          required: false },  // Bortle scale 1-9; 1=darkest (best), 9=brightest (worst); ≤4 = rural sky — NOTE: parse.js hardcodes 0, so this trivially passes and is inert until an astronomy data source is integrated
  },
};

const starGazing = [starGazingLite];

module.exports = { starGazing };
```

### 4.5 `src/weather/adapters/meteosource.js`

Add a `forecastStart` extractor. The `date` field on each hourly row is an ISO 8601 string like `"2026-05-19T15:00:00"`. Replace the entire file:

```js
const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
  forecastStart:    (firstRow) => firstRow.date,
  hour:       (h) => parseInt(h.date.split("T")[1].split(":")[0], 10),
  temp:       (h) => h.temperature,
  humidity:   (h) => h.humidity,
  windSpeed:  (h) => h.wind.speed,
  rainFall:   (h) => h.precipitation.total,
  cloudCover: (h) => h.cloud_cover?.total ?? h.cloud_cover,
  visibility: (h) => h.visibility,
  uV:         (h) => h.uv_index,
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
```

### 4.6 `src/weather/parse.js`

Change return shape from bare array to `{ forecastStart, hours }`. Replace the entire file:

```js
function parseWeather(rawResponse, adapter) {
  const phase = adapter.extractMoonPhase(rawResponse);
  const moon = phase ? [phase] : [];

  const allHours = adapter.extractHours(rawResponse);
  const forecastStart = adapter.forecastStart(allHours[0]);

  const hours = allHours.slice(0, 24).map((row) => ({
    hour:         adapter.hour(row),
    temp:         adapter.temp(row),
    humidity:     adapter.humidity(row),
    windSpeed:    adapter.windSpeed(row),
    rainFall:     adapter.rainFall(row),
    cloudCover:   adapter.cloudCover(row),
    visibility:   adapter.visibility(row),
    moon,
    uV:           adapter.uV(row),
    dustAlert:    adapter.dustAlert(row),
    // PENDING Issue #7 — wire real marine data from Meteosource adapter
    // douglasScale, swellHeight, swellLength, seaWarning are placeholder values.
    // Fishing activity ratings will trivially pass these thresholds until real data is integrated.
    darkness:     0,       // PENDING: astronomy data source (not Meteosource)
    douglasScale: 0,       // PENDING Issue #7: Meteosource marine data
    swellHeight:  0,       // PENDING Issue #7: Meteosource marine data
    swellLength:  0,       // PENDING Issue #7: Meteosource marine data
    tide:         0,       // DEFERRED: requires separate tidal API — no data source identified
    seaWarning:   false,   // PENDING: UAE maritime authority API — not Meteosource
  }));

  return { forecastStart, hours };
}

module.exports = { parseWeather };
```

### 4.7 `index.js`

Update the `parseWeather` call to destructure the new return shape. Replace lines 29–32:

```js
const { hours } = parseWeather(raw, meteosourceAdapter);

const window = evaluate(hours, sampleUserPrefs);
console.log(JSON.stringify(window, null, 2));
```

No other changes to `index.js`.

### 4.8 `src/activities/index.js`

Flatten the export from an object of arrays to a single array. This removes the grouping artefact and makes `evaluateAll.js` a simple single-level loop:

```js
const { fishing } = require("./fishing");
const { starGazing } = require("./starGazing");
const { volleyBall } = require("./volleyBall");

const activities = [...fishing, ...starGazing, ...volleyBall];

module.exports = { activities };
```

### 4.9 `src/decision/evaluateAll.js` (new file)

```js
const { evaluate } = require('./decision_engine');
const { activities } = require('../activities/index');

function evaluateAll(hours) {
  const results = [];

  for (const activity of activities) {
    const window = evaluate(hours, {
      activityId: activity.id,
      thresholds: activity.thresholds,
    });
    results.push({
      ...window,
      label: activity.label,
      displayMetrics: activity.displayMetrics,
    });
  }

  return results;
}

module.exports = { evaluateAll };
```

---

## 5. Acceptance criteria

- [ ] `npm test` still passes — all five existing tests in `tests/decision/decision_engine.test.js` succeed unchanged.
- [ ] `node index.js` runs against the live API and prints valid JSON (use `node index.js | python3 -m json.tool` to verify).
- [ ] `tests/decision/evaluateAll.test.js` exists and passes — smoke test verifies `evaluateAll(hours)` returns an array where every element contains `activityId`, `label`, `rating`, and `displayMetrics`.
- [ ] `grep -r "tempMax\|tempMin\|windMax\|humidityMax\|uvMax" src/activities/` returns nothing — old flat field names are gone.
- [ ] `grep -r "forbidTrue" src/activities/` returns at least 2 lines (volleyball dustAlert, fishing seaWarning entries).
- [ ] `src/activities/volleyBall.js` exports an array, not a plain object — verify with `node -e "const {volleyBall} = require('./src/activities/volleyBall'); console.log(Array.isArray(volleyBall))"` prints `true`.
- [ ] `src/activities/index.js` exports a flat array — verify with `node -e "const {activities} = require('./src/activities'); console.log(Array.isArray(activities), activities.length)"` prints `true 5` (volleyball, boat-fishing-pro, boat-fishing-lite, shore-fishing, stargazing-lite).

---

## 6. Related artifacts

- [`CONTEXT.md`](../../CONTEXT.md) — domain glossary.
- [Issue #1 (completed)](../completed/implement-spec-issue-1.md) ([GitHub](https://github.com/1mposer/time-it/issues/1)) — fixed the midnight-crossover bug; established the `startIndex`/`endIndex`/`duration` output contract that this issue builds on.
- [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — must be completed after this issue; imports `evaluateAll` and `parseWeather`.
- [Issue #5a (iOS Core)](../current/implement-spec-issue-5a-ios-core.md) — depends on the JSON contract defined here (`forecastStart`, `displayMetrics`, `id`).
- [Issue #8 (requireTrue threshold)](implement-spec-issue-8-require-true-threshold.md) ([GitHub](https://github.com/1mposer/time-it/issues/8)) — depends on the `forbidTrue` flag type introduced here; adds its logical counterpart.
