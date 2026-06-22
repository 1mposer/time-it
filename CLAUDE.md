# time-it — codebase guide

Domain language is defined in [`docs/CONTEXT.md`](docs/CONTEXT.md). Read it before touching any logic. The terms **Pursuit**, **Activity**, **Threshold**, **Rating**, **Window**, **Index**, **Forecast start**, **Lite/Pro**, and **Display metrics** have precise meanings there.

Then, **before assuming any contract**, read [`docs/STATUS.md`](docs/STATUS.md) for the current project status — which terms/contracts describe code-as-it-exists vs locked-but-unbuilt design, and what is currently blocked. Order: **CLAUDE.md → CONTEXT.md (learn the terms) → STATUS.md (current status)**.

---

## What the system does

Fetches a 7-day rolling weather **Forecast** (hourly, up to 168 entries) for a lat/lon, evaluates it against every **Activity**'s **Threshold** profile, and returns a per-local-calendar-day **Rating** (the best **Window** found within each day) for each. Output is consumed by an iOS app (Issue #5) and later delivered as a push notification (Issue #6).

---

## Architecture — HTTP server + three deep modules

Callers import only the public surface of each module. Internal files (`fetch.js`, `parse.js`, `decision_engine.js`, individual activity files) are implementation details.

```
app.js                       →  entry point. Calls app.listen(PORT, '0.0.0.0')
src/server.js                →  Express app (exported, no .listen). CORS, health route, mounts router
src/routes/rating.js         →  createRatingRouter({ getWeather, evaluateAll })  →  GET /api/v1/rating

src/weather/index.js         →  getWeather(lat, lon)             returns { forecastStart, timezone, hours }
src/weather/UpstreamError.js →  UpstreamError                     typed provider-failure error
src/decision/index.js        →  evaluateAll(hours)                returns Activity result[] (per-day days[])
src/activities/index.js      →  activities                        flat array of all Activity objects
```

The full data flow is two steps:

```js
const { forecastStart, timezone, hours } = await getWeather(lat, lon);
const results = evaluateAll(hours);
```

`forecastStart` is an ISO 8601 UTC timestamp with a `Z` suffix (e.g. `"2026-06-10T14:00:00Z"`). `timezone` is the **forecast location's** IANA zone (e.g. `"Asia/Dubai"`). The iOS app combines `forecastStart` + `timezone` + each hourly **Index** to render local clock times and day labels in the *location's* zone — so they match the server's day bucketing (see [ADR-0004](docs/adr/0004-day-bucketed-rating-wire-shape.md)). The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode `forecastStart` without custom formatting.

Internally, `getWeather` tags each hour with a `localDay` key (the location's calendar day) via the **time-boundary module** so `evaluateAll` can bucket results by day; `localDay` is stripped before the wire.

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
  "timezone": "Asia/Dubai",
  "activities": [
    {
      "activityId": "boat-fishing-pro",
      "label": "Boat Fishing Pro",
      "displayMetrics": ["temp"],
      "days": [
        { "dayIndex": 0, "rating": "perfect", "startIndex": 3, "endIndex": 9, "duration": 6 },
        { "dayIndex": 1, "rating": null },
        { "dayIndex": 2, "rating": "good", "startIndex": 52, "endIndex": 55, "duration": 3 }
      ]
    },
    {
      "activityId": "stargazing-lite",
      "label": "Stargazing Lite",
      "displayMetrics": ["temp", "cloudCover"],
      "days": [
        { "dayIndex": 0, "rating": null },
        { "dayIndex": 1, "rating": null },
        { "dayIndex": 2, "rating": null }
      ]
    }
  ],
  "hours": [
    {
      "index": 0,
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

**Top-level field types:**
- `forecastStart`: `string` — ISO 8601 UTC with `Z` suffix; the instant of `hours[0]`.
- `timezone`: `string` — the forecast location's IANA zone (e.g. `"Asia/Dubai"`). The client renders clock times and day labels in **this** zone, not the device's.
- `activities`: `Activity[]` — one entry per **Activity**, in canonical dashboard order.
- `hours`: hourly forecast array — provider-determined length, **up to 168** (do not assume any fixed count).

**`activities[]` field types:**
- `activityId`, `label`: `string`
- `displayMetrics`: `string[]`
- `days`: `Day[]` — **one entry per forecast-location local calendar day**, dense and contiguous (`days[i].dayIndex === i`). Length is **7 or 8** and is **per-activity** — read each activity's own `days.length`; never assume `7`. The singular top-level `rating`/window is **gone** (ADR-0004). The card reads `days[0]`; the timeline reads all of `days[]`.

**`days[]` field types:**
- `dayIndex`: `number` — 0-based ordinal of the local calendar day (`0` = today, `1` = tomorrow…).
- `rating`: `"perfect" | "good" | null` — `null` means no qualifying **Window** that day.
- `startIndex`, `endIndex`, `duration`: `number` when `rating` is non-null; **absent from the object** when `rating` is `null`. `startIndex`/`endIndex` are **global indices into `hours[]`** (not day-relative).

**`hours[]` field types (provider-determined count, ≤168):**
- `index`: `number` — `0..N-1`, position in the array. (The UTC `hour` field is **dropped** — the client derives clock times from `forecastStart` + `timezone` + `index`.)
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
- `rating.js` — exports `createRatingRouter({ getWeather, evaluateAll })` factory. Mounts `GET /api/v1/rating?lat=&lon=` on a fresh Express router. Validates required params, calls injected `getWeather` and `evaluateAll`, then shapes the wire JSON: strips the internal `localDay` from each hour, prepends `index`, and assembles `{ forecastStart, timezone, activities, hours }`. Error mapping: `400` (missing/invalid params), `502` (`err instanceof UpstreamError` — provider failure), `500` (any other thrown error). Default dependencies resolve to the real modules; tests pass fakes via the factory arg.

### `src/weather/`
- `index.js` — public. Guards `process.env.API_KEY` (throws plain `Error` if missing), then fetch → parse → tags each hour with its `localDay` (via the time-boundary module) → returns `{ forecastStart, timezone, hours }`. Sends `timezone: 'auto'` in the upstream request — the only Meteosource mode that exposes the location IANA zone — and does not accept a timezone arg. Owns the Meteosource adapter selection and all API params.
- `fetch.js` — calls the Meteosource `flexi` REST endpoint (`/api/v1/flexi/point`, the 7-day tier; `/free/` caps at 24h). Wraps non-OK responses and network errors as `UpstreamError` so the route layer can map them to `502`.
- `parse.js` — normalises raw response to the unified hourly schema, capped at the `FORECAST_HOURS` ceiling (168) — fewer passes through; never fabricates hours. Throws `UpstreamError` if the provider returns no hourly data. Each hour gets its own copy of the `moon` array (no shared reference). Returns `{ forecastStart, timezone, hours }`.
- `timeBoundary.js` — the locale/time sibling of the adapter. `tagLocalDays(hours, forecastStart, timezone)` tags each hour with an internal `localDay` key (the forecast location's calendar day) computed from the UTC instant via `Intl` with an explicit `timeZone`; `localDay` is internal and never reaches the wire. Also exports `zonedWallTimeToUtcIso` — converts the provider's local wall-time (returned under `timezone=auto`) to a UTC-`Z` instant.
- `adapters/meteosource.js` — extracts provider-specific fields. Returns `null` (via `?? null`) for absent `wind.speed`, `precipitation.total`, and `cloud_cover.total` rather than letting `undefined` propagate. Extracts the top-level `timezone`; converts the provider's local wall-time `forecastStart` to UTC-`Z` via that zone (`timezone=auto` returns local timestamps, so a blind `Z`-append would be wrong). Swap this file to change weather provider without touching parse logic.
- `UpstreamError.js` — typed `Error` subclass (`name: 'UpstreamError'`) used to mark any provider-side failure (network, non-OK status, malformed payload, empty data). Route layer uses `instanceof` to map it to `502`.

### `src/decision/`
- `index.js` — public. Re-exports `evaluateAll`.
- `evaluateAll.js` — iterates all **Activities**. A thin per-day bucketing layer splits the flat `hours[]` into contiguous `localDay` runs (recording each bucket's global offset), calls `evaluate()` per day-slice, and offsets the slice-relative window back to **global `hours[]` indices**. Constructs each result with the documented field order: `activityId`, `label`, `displayMetrics`, `days[]`; each day is `{ dayIndex, rating, (startIndex, endIndex, duration) }`. Signature stays `evaluateAll(hours)` — activities are still hardcoded (the caller-supplied flip is Phase 2).
- `decision_engine.js` — core logic: `evaluateHour`, `findLongestWindow`, `evaluate`. Reused **unchanged** — `evaluateAll` calls `evaluate()` over each day's hour-slice. `checkThreshold` treats `null`/`undefined` values as failing the threshold (absent data fails rather than silently passing via NaN coercion). `findLongestWindow` uses strict `>` for tie-breaking, so on equal durations the earlier window wins. Do not import this directly from outside the module.

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
- `tests/decision/evaluateAll.test.js` — multi-activity evaluation; verifies count, per-activity `days[]` shape, dense contiguous `dayIndex`, stable IDs, flag threshold behaviour per day, the null-day convention, and — critically — that per-day window indices are **global** (a qualifying window on day ≥1 catches a missing per-day offset).
- `tests/weather/timeBoundary.test.js` — unit tests for the time-boundary module. Tags hours with `localDay` against the ADR-0003 worked example (164 hours from `2026-06-19T12:00:00Z`, `Asia/Dubai` → 8 buckets of 8/24×6/12); the UTC-instant landmine guard (host timezone must not shift buckets); and `zonedWallTimeToUtcIso` (local wall-time → UTC-`Z`, no millis, idempotent on already-zoned input).
- `tests/weather/adapter.test.js` — unit tests for the Meteosource adapter. Per-field coverage: `windSpeed`/`rainFall`/`cloudCover` returning `null` when the upstream payload omits the source field; the `timezone` extractor; `forecastStart` converting the provider's local wall-time to UTC-`Z` via the zone (idempotent on already-UTC-`Z`).
- `tests/weather/parse.test.js` — unit tests for `parseWeather`. Covers the 168-hour ceiling slice (and pass-through of a smaller provider count), `timezone` passthrough, the `UpstreamError` on empty hourly data, per-hour `moon` array isolation, placeholder defaults, and a contract pin on the per-hour key order (no `hour`).
- `tests/weather/fetch.test.js` — unit tests for `fetchWeather`. Wraps network failures and non-OK responses as `UpstreamError`.
- `tests/weather/getWeather.test.js` — unit tests for the public `getWeather`. Includes the `API_KEY` guard, confirmation that it sends `timezone=auto` and targets the `flexi` endpoint, and that it surfaces `timezone` plus an internal `localDay` per hour.
- `tests/server/health.test.js` — 1 test: `GET /health` returns `200` with `status: ok`.
- `tests/server/rating.test.js` — integration tests for the route. Uses the `createRatingRouter({ getWeather, evaluateAll })` factory to inject fakes — no live API calls and no `require.cache` patching. Covers param-validation 400s, the day-bucketed response shape (top-level `timezone` + per-hour `index` with `localDay` stripped and `hour` dropped + per-activity `days[]`), the null-day wire convention, a partial-day-0 fixture (variable-length buckets + non-24 global offset), `UpstreamError → 502` mapping, generic `Error → 500` mapping, and the silently-ignored `timezone` query param. Includes a golden snapshot test pinning the full response shape, activity-array order, per-object key order, and global window indices against the documented contract.

---

## Running the server

```
npm run dev        # nodemon — auto-restarts on file save (development)
npm start          # node app.js (production)
```

`GET /health` — liveness check (used by Railway).
`GET /api/v1/rating?lat=25.1627&lon=55.2077` — returns the 7-day forecast + per-day ratings for all activities.

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
