# time-it — codebase guide

Domain language is defined in [`docs/CONTEXT.md`](docs/CONTEXT.md). Read it before touching any logic. The terms **Pursuit**, **Activity**, **Threshold**, **Rating**, **Window**, **Index**, **Forecast start**, **Lite/Pro**, and **Display metrics** have precise meanings there.

Then, **before assuming any contract**, read [`docs/STATUS.md`](docs/STATUS.md) for the current project status — which terms/contracts describe code-as-it-exists vs locked-but-unbuilt design, and what is currently blocked. Order: **CLAUDE.md → CONTEXT.md (learn the terms) → STATUS.md (current status)**.

---

## What the system does

Fetches a 24-hour weather **Forecast** for a lat/lon, evaluates it against every **Activity**'s **Threshold** profile, and returns the best **Window** for each. Output is consumed by an iOS app (Issue #5) and later delivered as a push notification (Issue #6).

---

## Architecture — HTTP server + three deep modules

Callers import only the public surface of each module. Internal files (`fetch.js`, `parse.js`, `decision_engine.js`, individual activity files) are implementation details.

```
app.js                       →  entry point. Calls app.listen(PORT, '0.0.0.0')
src/server.js                →  Express app (exported, no .listen). CORS, health route, mounts router
src/routes/rating.js         →  createRatingRouter({ getWeather, evaluateAll })  →  GET /api/v1/rating

src/weather/index.js         →  getWeather(lat, lon)             returns { forecastStart, hours }
src/weather/UpstreamError.js →  UpstreamError                     typed provider-failure error
src/decision/index.js        →  evaluateAll(hours)                returns Activity result[]
src/activities/index.js      →  activities                        flat array of all Activity objects
```

The full data flow is two steps:

```js
const { forecastStart, hours } = await getWeather(lat, lon);
const results = evaluateAll(hours);
```

`forecastStart` is an ISO 8601 UTC timestamp with a `Z` suffix (e.g. `"2026-06-10T14:00:00Z"`) — the iOS app combines it with each hourly **Index** to render local clock times. The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode it without custom formatting.

---

## API response contract

The HTTP API has two routes. Treat the shapes below as the contract — the iOS client (Issue #5a) decodes against them.

### `GET /health`

```json
{ "status": "ok", "timestamp": "2026-06-10T14:00:00.000Z" }
```

Always returns `200`. Used by Railway liveness check.

### `GET /api/v1/rating?lat=<number>&lon=<number>`

**Success — `200`:**

```json
{
  "forecastStart": "2026-06-10T14:00:00Z",
  "activities": [
    {
      "activityId": "boat-fishing-pro",
      "label": "Boat Fishing Pro",
      "displayMetrics": ["temp"],
      "rating": "perfect",
      "startIndex": 3,
      "endIndex": 9,
      "duration": 6
    },
    {
      "activityId": "stargazing-lite",
      "label": "Stargazing Lite",
      "displayMetrics": ["temp", "cloudCover"],
      "rating": null
    }
  ],
  "hours": [
    {
      "index": 0,
      "hour": 14,
      "temp": 32,
      "humidity": 55,
      "windSpeed": 12,
      "rainFall": 0,
      "cloudCover": 25,
      "visibility": 10,
      "moon": ["waxing crescent"],
      "uV": 6,
      "dustAlert": false,
      "darkness": 0,
      "douglasScale": 0,
      "swellHeight": 0,
      "swellLength": 0,
      "tide": 0,
      "seaWarning": false
    }
  ]
}
```

**`activities[]` field types:**
- `activityId`, `label`: `string`
- `displayMetrics`: `string[]`
- `rating`: `"perfect" | "good" | null` — `null` means no qualifying **Window** was found
- `startIndex`, `endIndex`, `duration`: `number` when `rating` is non-null; **absent from the object** when `rating` is `null`

**`hours[]` field types (24 entries):**
- `index`: `number` — 0..23, position in the array
- `hour`: `number` — 0..23, UTC clock hour
- `temp`, `humidity`, `visibility`, `uV`: `number`
- `windSpeed`, `rainFall`, `cloudCover`: `number | null` — `null` when the upstream provider omitted the field. iOS decoders **must** model these as optional.
- `moon`: `string[]` — moon phase labels, possibly empty
- `dustAlert`, `seaWarning`: `boolean`
- `darkness`, `douglasScale`, `swellHeight`, `swellLength`, `tide`: `number` — currently hardcoded placeholders (see [Pending / placeholder data](#pending--placeholder-data) below)

**Error responses:**

| Status | When | Body |
|---|---|---|
| `400` | Missing `lat` or `lon` query param | `{ "error": "Missing required parameter: lat" }` (or `lon`) |
| `502` | Weather provider failed (network error, non-OK status, malformed payload, empty data) | `{ "error": "Weather data unavailable" }` |
| `500` | Any other unexpected error | `{ "error": "Internal server error" }` |

Clients should distinguish `502` (transient — retry, or fall back to a different provider in future) from `500` (server defect — surface differently).

---

## Module internals

### `src/routes/`
- `rating.js` — exports `createRatingRouter({ getWeather, evaluateAll })` factory. Mounts `GET /api/v1/rating?lat=&lon=` on a fresh Express router. Validates required params, calls injected `getWeather` and `evaluateAll`, adds `index` field to each hour, returns shaped JSON. Error mapping: `400` (missing/invalid params), `502` (`err instanceof UpstreamError` — provider failure), `500` (any other thrown error). Default dependencies resolve to the real modules; tests pass fakes via the factory arg.

### `src/weather/`
- `index.js` — public. Guards `process.env.API_KEY` (throws plain `Error` if missing), then calls fetch → parse → returns `{ forecastStart, hours }`. Hardcodes `timezone: 'UTC'` in the upstream request — does not accept a timezone arg. Owns the Meteosource adapter selection and all API params.
- `fetch.js` — calls Meteosource REST API. Wraps non-OK responses and network errors as `UpstreamError` so the route layer can map them to `502`.
- `parse.js` — normalises raw response to the unified hourly schema (24 entries). Throws `UpstreamError` if the provider returns no hourly data. Each hour gets its own copy of the `moon` array (no shared reference). Returns `{ forecastStart, hours }`.
- `adapters/meteosource.js` — extracts provider-specific fields. Returns `null` (via `?? null`) for absent `wind.speed`, `precipitation.total`, and `cloud_cover.total` rather than letting `undefined` propagate. Throws `UpstreamError` on malformed dates. Appends `Z` to `forecastStart` if not already present. Swap this file to change weather provider without touching parse logic.
- `UpstreamError.js` — typed `Error` subclass (`name: 'UpstreamError'`) used to mark any provider-side failure (network, non-OK status, malformed payload, empty data). Route layer uses `instanceof` to map it to `502`.

### `src/decision/`
- `index.js` — public. Re-exports `evaluateAll`.
- `evaluateAll.js` — iterates all **Activities**, calls `evaluate()` per activity, and constructs each result with the documented field order: `activityId`, `label`, `displayMetrics`, `rating`, and (only when `rating` is non-null) `startIndex`, `endIndex`, `duration`.
- `decision_engine.js` — core logic: `evaluateHour`, `findLongestWindow`, `evaluate`. `checkThreshold` treats `null`/`undefined` values as failing the threshold (absent data fails rather than silently passing via NaN coercion). `findLongestWindow` uses strict `>` for tie-breaking, so on equal durations the earlier window wins. Do not import this directly from outside the module.

### `src/activities/`
- `index.js` — public. Exports a flat `activities` array: `[...fishing, ...volleyBall, ...starGazing]`. Order is the canonical dashboard order documented in `docs/issues/current/design-decisions-issue-5.md`.
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

- `tests/decision/decision_engine.test.js` — unit tests for core **Window** logic. Covers midnight crossover, single-hour windows, no qualifying hours, Perfect-preferred-over-Good, last-element runs. Also covers the B2 null-guard (`null`/`undefined` values fail thresholds) and the strict-`>` tie-break (earlier window wins).
- `tests/decision/evaluateAll.test.js` — smoke test for multi-activity evaluation; verifies count, shape, stable IDs, flag threshold behaviour, and that the entry point exposes `evaluateAll` without leaking internals.
- `tests/weather/adapter.test.js` — unit tests for the Meteosource adapter. Per-field coverage: `windSpeed`/`rainFall`/`cloudCover` returning `null` when the upstream payload omits the source field; `hour` throwing `UpstreamError` on malformed dates; `forecastStart` appending `Z` (idempotently) for unambiguous UTC.
- `tests/weather/parse.test.js` — unit tests for `parseWeather`. Covers the 24-hour slice, the `UpstreamError` on empty hourly data, per-hour `moon` array isolation, placeholder defaults, and a contract pin on the per-hour key order.
- `tests/weather/fetch.test.js` — unit tests for `fetchWeather`. Wraps network failures and non-OK responses as `UpstreamError`.
- `tests/weather/getWeather.test.js` — unit tests for the public `getWeather`. Includes the `API_KEY` guard and confirmation that no timezone arg leaks into the upstream URL.
- `tests/server/health.test.js` — 1 test: `GET /health` returns `200` with `status: ok`.
- `tests/server/rating.test.js` — integration tests for the route. Uses the `createRatingRouter({ getWeather, evaluateAll })` factory to inject fakes — no live API calls and no `require.cache` patching. Covers param-validation 400s, response shape (top-level + per-hour `index` + per-activity window fields), `UpstreamError → 502` mapping, generic `Error → 500` mapping, and the fact that a `timezone` query param is silently ignored. Includes a golden snapshot test pinning the full response shape, activity-array order, and per-object key order against the documented contract.

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

- **Done:** Issue #3 (backend internals), Issue #4 (HTTP API — Express server, `GET /api/v1/rating`), Issue #10 (pre-5a hardening — typed provider errors, null-safe adapter, DI factory router, expanded test coverage)
- **Next:** Issue #5a (core iOS SwiftUI app — requires this server running locally on `localhost:3000`)
- **Then:** Issue #5b (iOS personalization), Issue #6 (deploy + APNs)
- **Parallel:** Issue #7 (marine data), Issue #8 (`requireTrue` flag type)
