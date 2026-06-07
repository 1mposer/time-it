# time-it — codebase guide

Domain language is defined in [`docs/CONTEXT.md`](docs/CONTEXT.md). Read it before touching any logic. The terms **Pursuit**, **Activity**, **Threshold**, **Rating**, **Window**, **Index**, **Forecast start**, **Lite/Pro**, and **Display metrics** have precise meanings there.

---

## What the system does

Fetches a 24-hour weather **Forecast** for a lat/lon, evaluates it against every **Activity**'s **Threshold** profile, and returns the best **Window** for each. Output is consumed by an iOS app (Issue #5) and later delivered as a push notification (Issue #6).

---

## Architecture — HTTP server + three deep modules

Callers import only the public surface of each module. Internal files (`fetch.js`, `parse.js`, `decision_engine.js`, individual activity files) are implementation details.

```
app.js                    →  entry point. Calls app.listen(PORT, '0.0.0.0')
src/server.js             →  Express app (exported, no .listen). CORS, health route, mounts router
src/routes/rating.js      →  GET /api/v1/rating — validates params, calls weather + decision, returns JSON

src/weather/index.js      →  getWeather(lat, lon, timezone?)  returns { forecastStart, hours }
src/decision/index.js     →  evaluateAll(hours)               returns Activity result[]
src/activities/index.js   →  activities                       flat array of all Activity objects
```

The full data flow is two steps:

```js
const { forecastStart, hours } = await getWeather(lat, lon, timezone);
const results = evaluateAll(hours);
```

`forecastStart` is an ISO 8601 UTC timestamp — the iOS app combines it with each hourly **Index** to render local clock times.

---

## Module internals

### `src/routes/`
- `rating.js` — `GET /api/v1/rating?lat=&lon=&timezone=`. Validates required params, calls `getWeather` and `evaluateAll`, adds `index` field to each hour, returns shaped JSON. Error → 400 (bad params), 502 (Meteosource failure), 500 (unexpected).

### `src/weather/`
- `index.js` — public. Calls fetch → parse → returns `{ forecastStart, hours }`. Accepts optional `timezone` (default `"UTC"`). Owns the Meteosource adapter selection and all API params.
- `fetch.js` — calls Meteosource REST API. Reads `process.env.API_KEY`.
- `parse.js` — normalises raw response to the unified hourly schema (24 entries). Returns `{ forecastStart, hours }`.
- `adapters/meteosource.js` — extracts provider-specific fields. Swap this file to change weather provider without touching parse logic.

### `src/decision/`
- `index.js` — public. Re-exports `evaluateAll`.
- `evaluateAll.js` — iterates all **Activities**, calls `evaluate()` per activity, merges in `label` and `displayMetrics`.
- `decision_engine.js` — core logic: `evaluateHour`, `findLongestWindow`, `evaluate`. Do not import this directly from outside the module.

### `src/activities/`
- `index.js` — public. Exports a flat `activities` array: `[...fishing, ...starGazing, ...volleyBall]`.
- `volleyBall.js`, `fishing.js`, `starGazing.js` — activity definitions. Each file exports an array (even single-activity pursuits).

---

## Activity object shape

Every activity in the flat array must have:

```js
{
  id:             "kebab-case-string",   // stable; used as activityId in engine output
  label:          "Human Label",
  displayMetrics: ["temp", "windSpeed"], // iOS renders only these fields per card
  thresholds: {
    temp:      { min: 15, max: 35, required: true  },
    windSpeed: {          max: 15, required: false },
    dustAlert: { type: "flag", forbidTrue: true, required: true },
  },
}
```

Threshold rules:
- Numeric fields: `min`, `max`, `required` — omit whichever bound is unconstrained.
- Boolean fields: `type: "flag"`, `forbidTrue: true` — fails the hour when the field is `true`.
- `required: true` → failing makes the hour **Bad**. `required: false` → failing makes it **Good** instead of **Perfect**.

---

## Adding a new Activity

1. Add a definition object to the relevant file in `src/activities/` (or create a new file for a new Pursuit).
2. Ensure the file exports an array.
3. Spread the array into `src/activities/index.js`.
4. Run `npm test` — `evaluateAll.test.js` checks `activities.length`; update the count assertion if it changes.

---

## Pending / placeholder data

Several hourly fields are hardcoded in `parse.js` pending real data sources. Activities that threshold against these fields will trivially pass until the issues below are resolved:

| Field | Value | Blocked on |
|---|---|---|
| `douglasScale` | `0` | Issue #7 (Meteosource marine tier) |
| `swellHeight` | `0` | Issue #7 |
| `swellLength` | `0` | Issue #7 |
| `seaWarning` | `false` | UAE maritime authority API — no source identified |
| `darkness` | `0` | Astronomy data source — not Meteosource |
| `tide` | `0` | Separate tidal API — deferred |

---

## Tests

```
npm test
```

- `tests/decision/decision_engine.test.js` — 5 unit tests for core **Window** logic.
- `tests/decision/evaluateAll.test.js` — smoke test for multi-activity evaluation; verifies count, shape, stable IDs, and flag threshold behaviour.
- `tests/server/health.test.js` — 1 test: `GET /health` returns 200 with `status: ok`.
- `tests/server/rating.test.js` — 5 tests: param validation (400s), top-level response shape, `hours` index field, activity shape including window fields. Uses `require.cache` injection to mock `getWeather` — no live API calls.

---

## Running the server

```
npm run dev        # nodemon — auto-restarts on file save (development)
npm start          # node app.js (production)
```

`GET /health` — liveness check (used by Railway).
`GET /api/v1/rating?lat=25.1627&lon=55.2077` — returns forecast + all activity ratings.

Requires `.env` with `API_KEY=<meteosource key>` and optionally `PORT=3000`. See `.env.example`.

## CLI (development only)

`cli.js` at the root hits the live Meteosource API and prints a single-activity evaluation as JSON:

```
node cli.js | python3 -m json.tool
```

Requires `.env` with `API_KEY=<meteosource key>`.

---

## Current build order

See [`docs/issues/ROADMAP.md`](docs/issues/ROADMAP.md) for the full critical path.

- **Done:** Issue #3 (backend internals), Issue #4 (HTTP API — Express server, `GET /api/v1/rating`)
- **Next:** Issue #5 (iOS SwiftUI app — requires this server running locally)
- **Then:** Issue #6 (deploy + APNs)
- **Parallel:** Issue #7 (marine data), Issue #8 (`requireTrue` flag type)
