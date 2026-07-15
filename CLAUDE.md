# time-it — codebase guide

Domain language is defined in [`docs/CONTEXT.md`](docs/CONTEXT.md). Read it before touching any logic. The terms **Pursuit**, **Activity**, **Threshold**, **Rating**, **Window**, **Index**, **Forecast start**, **Lite/Pro**, and **Display metrics** have precise meanings there.

Then, **before assuming any contract**, read [`docs/STATUS.md`](docs/STATUS.md) for the current project status — which terms/contracts describe code-as-it-exists vs locked-but-unbuilt design, and what is currently blocked. Order: **CLAUDE.md → CONTEXT.md (learn the terms) → STATUS.md (current status)**.

---

## What the system does

Accepts a `POST` with a `lat`/`lon` and a list of **caller-supplied Activities** (each with a **Threshold** profile and an optional time-of-day **Window**), fetches a 7-day rolling weather **Forecast** (hourly, up to 168 entries) for that location, evaluates the forecast against every Activity, and returns a per-local-calendar-day **Rating** (the best **Window** found within each day) for each. The engine holds **no** activity list — activities are authored client-side and sent in the request body ([ADR-0002](docs/adr/0002-activity-agnostic-engine.md), [ADR-0005](docs/adr/0005-custom-activity-request-schema.md)). Output is consumed by an iOS app (Issue #5) and later delivered as a push notification (Issue #6).

---

## Architecture — HTTP server + three deep modules

Callers import only the public surface of each module. Internal files (`fetch.js`, `parse.js`, `decision_engine.js`, individual activity files) are implementation details.

```
app.js                          →  entry point. Calls app.listen(PORT, '0.0.0.0')
src/server.js                   →  Express app (exported, no .listen). CORS, express.json(), health route, mounts router
src/routes/rating.js            →  createRatingRouter({ getWeather, evaluateAll })  →  POST /api/v1/rating
src/routes/validateRatingRequest.js →  validateRatingRequest(body)  returns structured error[] (ADR-0005 §6)

src/weather/index.js         →  getWeather(lat, lon)             returns { forecastStart, timezone, hours }
src/weather/metricCatalog.js →  LIVE/COMING_SOON metric sets     isKnown / isAvailable (validation source of truth)
src/weather/UpstreamError.js →  UpstreamError                     typed provider-failure error
src/decision/index.js        →  evaluateAll(hours, activities)    returns Activity result[] (per-activity days[])
```

There is **no** `src/activities/` module — activities are caller-supplied in the request body (deleted in Phase 2; the curated list moves to client-side Templates per [ADR-0002](docs/adr/0002-activity-agnostic-engine.md)).

The full data flow is two steps (the route validates the body first, then):

```js
const { forecastStart, timezone, hours } = await getWeather(lat, lon);
const results = evaluateAll(hours, activities); // activities come from the POST body
```

`forecastStart` is an ISO 8601 UTC timestamp with a `Z` suffix (e.g. `"2026-06-10T14:00:00Z"`). `timezone` is the **forecast location's** IANA zone (e.g. `"Asia/Dubai"`). The iOS app combines `forecastStart` + `timezone` + each hourly **Index** to render local clock times and day labels in the *location's* zone — so they match the server's day bucketing (see [ADR-0004](docs/adr/0004-day-bucketed-rating-wire-shape.md)). The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode `forecastStart` without custom formatting.

Internally, `getWeather` tags each hour with a `localDay` key (the location's calendar day) and a `localHour` key (0–23 in the location's zone) via the **time-boundary module** so `evaluateAll` can bucket results by day and filter/stitch time-of-day **Windows**; both `localDay` and `localHour` are internal and stripped before the wire.

---

## API response contract

The HTTP API has two routes. Treat the shapes below as the contract — the iOS client (Issue #5a) decodes against them.

### `GET /health`

```json
{ "status": "ok", "timestamp": "2026-06-10T14:00:00.000Z" }
```

Always returns `200`. Used by Railway liveness check.

### `POST /api/v1/rating`

The engine is activity-agnostic ([ADR-0002](docs/adr/0002-activity-agnostic-engine.md)): the caller **sends** the Activities to evaluate in a JSON body. `lat`/`lon` move out of the query string into the body; there is **no** `timezone` in the request (the location's zone is resolved server-side from `lat`/`lon`). See [ADR-0005](docs/adr/0005-custom-activity-request-schema.md).

**Request body:**

```json
{
  "lat": 25.1627,
  "lon": 55.2077,
  "activities": [
    {
      "id": "9f3a0c1e-…",
      "label": "Stargazing",
      "displayMetrics": ["temp", "cloudCover", "humidity"],
      "thresholds": {
        "temp":       { "min": 10, "max": 30, "required": true },
        "cloudCover": { "max": 20, "required": true }
      },
      "window": { "startHour": 22, "endHour": 2 }
    }
  ]
}
```

**Request field types:**
- `lat`/`lon`: `number` — required, in `-90..90` / `-180..180`.
- `activities`: `Activity[]` — required, non-empty, hard ceiling **~50** (a DoS guard, **not** a tier/quantity gate — tier limits are client-enforced).
- `id`: `string` — client-authored, **unique within the request**, echoed verbatim into the response `activityId`.
- `label`: `string` — required, non-empty, echoed.
- `displayMetrics`: `string[]` — required, non-empty render **superset** (ordered); echoed.
- `thresholds`: keyed map — the **evaluated subset**; `thresholds.keys ⊆ displayMetrics` (the gap is "show-but-don't-judge"). Numeric `{ min?, max?, required }` (≥1 bound); flag `{ type:"flag", forbidTrue:true, required }`. `required` is mandatory; `requireTrue` is rejected (Issue #8).
- `window` (optional): `{ startHour, endHour }` integers `0..23` in **location-local** hours, half-open `[startHour, endHour)`. Absent = whole day; `startHour < endHour` = same-day; `startHour > endHour` = **midnight-wrap (nocturnal → night-stitch)**; `startHour === endHour` is rejected. `window` is **input-only** — it is *not* echoed in the response.

Validation is **atomic** (one bad activity rejects the whole request, `400`) and **structured** (see error table). An **unknown or coming-soon metric** in either `displayMetrics` or `thresholds` is a hard `400` (the false-Perfect backstop — a threshold on placeholder data would pass trivially).

**Success — `200`:** (`activityId`/`label`/`displayMetrics` echo the request; the example IDs below are illustrative caller-supplied values)

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
- `activities`: `Activity[]` — one entry per request Activity, **echoed in request order**.
- `hours`: hourly forecast array — provider-determined length, **up to 168** (do not assume any fixed count).

**`activities[]` field types:**
- `activityId`, `label`: `string` — echoed from the request `id`/`label`.
- `displayMetrics`: `string[]` — echoed from the request.
- `days`: `Day[]` — dense and contiguous (`days[i].dayIndex === i`), **per-activity length** — read each activity's own `days.length`; never assume `7`. A **diurnal** activity buckets by local calendar day (length **7 or 8**); a **nocturnal** activity (wrapped `window`) buckets by **night** (one shorter — the tail day has no evening), so two activities in the same response can legitimately have different `days.length` (ADR-0004 amendment). The singular top-level `rating`/window is **gone** (ADR-0004). The card reads `days[0]`; the timeline reads all of `days[]`.

**`days[]` field types:**
- `dayIndex`: `number` — 0-based ordinal of the local calendar day (`0` = today, `1` = tomorrow…). For a nocturnal activity it is the **evening's** day ordinal (`0` = tonight); the wrapped window's early-morning tail is attributed to its evening, not the next day.
- `rating`: `"perfect" | "good" | null` — `null` means no qualifying **Window** that day.
- `startIndex`, `endIndex`, `duration`: `number` when `rating` is non-null; **absent from the object** when `rating` is `null`. `startIndex`/`endIndex` are **global indices into `hours[]`** (not day-relative).

**`hours[]` field types (provider-determined count, ≤168):**
- `index`: `number` — `0..N-1`, position in the array. (The UTC `hour` field is **dropped** — the client derives clock times from `forecastStart` + `timezone` + `index`.)
- `temp`, `humidity`, `visibility`, `uV`: `number` — `uV` is `0` at night (Meteosource returns `uv_index: null` after dark; the adapter defaults it to `0`, which is semantically correct, so it stays non-null on the wire).
- `windSpeed`, `rainFall`, `cloudCover`: `number | null` — `null` when the upstream provider omitted the field. iOS decoders **must** model these as optional. **Client hardening (2026-07-12):** the iOS decoder now models **every** metric as optional and tolerates a `null`/missing value on any of them (renders "—"), so a single unexpected provider null can never fail the whole decode — defence-in-depth beyond this contract.
- `moon`: `string[]` — moon phase labels, possibly empty
- `dustAlert`, `seaWarning`: `boolean`
- `darkness`, `douglasScale`, `swellHeight`, `swellLength`, `tide`: `number` — currently hardcoded placeholders (see [Pending / placeholder data](#pending--placeholder-data) below)

**Error responses.** Every error body is a **uniform structured array** `{ "errors": [ { "path"?, "message" } ] }` so the iOS decoder parses one shape across all codes (ADR-0005 §6); only the validation `400` carries `path` — the malformed-JSON `400`, `413`, `502`, and `500` are single-element arrays with no `path` (ADR-0004).

| Status | When | Body |
|---|---|---|
| `400` | Body-validation failure (missing/out-of-range `lat`/`lon`, empty/oversized `activities`, missing `label`/`id`, duplicate `id`, empty `displayMetrics`, `thresholds.keys ⊄ displayMetrics`, unknown/coming-soon metric, `min > max`, bound-less numeric, missing `required`, `requireTrue`, bad `window` hours, `startHour === endHour`) | `{ "errors": [ { "path": "activities[2].thresholds.temp", "message": "min greater than max" } ] }` |
| `400` | Malformed JSON body (`express.json()` parse failure — body is not valid JSON) | `{ "errors": [ { "message": "Malformed JSON in request body" } ] }` |
| `413` | Request body exceeds the `express.json()` size limit | `{ "errors": [ { "message": "Request body too large" } ] }` |
| `502` | Weather provider failed (network error, non-OK status, malformed payload, empty data) | `{ "errors": [ { "message": "Weather data unavailable" } ] }` |
| `500` | Any other unexpected error | `{ "errors": [ { "message": "Internal server error" } ] }` |

Validation is **atomic** — all failures are collected, so a `400` may list multiple errors. Clients should distinguish `502` (transient — retry, or fall back to a different provider in future) from `500` (server defect — surface differently).

---

## Module internals

### `src/routes/`
- `rating.js` — exports `createRatingRouter({ getWeather, evaluateAll })` factory. Mounts `POST /api/v1/rating` on a fresh Express router. **Validates the JSON body via `validateRatingRequest` BEFORE calling `getWeather`** (a malformed request spends no provider call); on any error returns `400` with the structured `{ errors }` array. Otherwise calls injected `getWeather(lat, lon)` and `evaluateAll(hours, activities)`, then shapes the wire JSON: strips the internal `localDay`/`localHour` from each hour, prepends `index`, and assembles `{ forecastStart, timezone, activities, hours }`. Error mapping (all bodies are the uniform `{ errors }` envelope): `400` (validation), `502` (`err instanceof UpstreamError` — provider failure), `500` (any other thrown error). Default dependencies resolve to the real modules; tests pass fakes via the factory arg.
- `validateRatingRequest.js` — exports `validateRatingRequest(body)` → array of `{ path, message }` (empty = valid). Atomic (collects every failure across the whole body, never first-wins) and structured per [ADR-0005 §6](docs/adr/0005-custom-activity-request-schema.md). Imports the metric catalog to hard-reject unknown/coming-soon metrics in either `displayMetrics` or `thresholds` (the false-Perfect backstop). The route maps a non-empty result to a single `400`.

### `src/weather/`
- `index.js` — public. Guards `process.env.API_KEY` (throws plain `Error` if missing), then fetch → parse → tags each hour with its `localDay` **and `localHour`** (via the time-boundary module) → returns `{ forecastStart, timezone, hours }`. Sends `timezone: 'auto'` in the upstream request — the only Meteosource mode that exposes the location IANA zone — and does not accept a timezone arg. Owns the Meteosource adapter selection and all API params.
- `metricCatalog.js` — the server-side source of truth for which metrics exist and which carry **live** data vs a **coming-soon** placeholder (`LIVE_METRICS`, `COMING_SOON_METRICS`, `isKnown`, `isAvailable`). `validateRatingRequest` imports it to hard-reject a threshold/display on a non-live metric (the false-Perfect guard). Kept separate so the deferred `GET /api/v1/metrics` catalog route (ADR-0006) can read the same source.
- `fetch.js` — calls the Meteosource `flexi` REST endpoint (`/api/v1/flexi/point`, the 7-day tier; `/free/` caps at 24h). Wraps non-OK responses and network errors as `UpstreamError` so the route layer can map them to `502`.
- `parse.js` — normalises raw response to the unified hourly schema, capped at the `FORECAST_HOURS` ceiling (168) — fewer passes through; never fabricates hours. Throws `UpstreamError` if the provider returns no hourly data. Each hour gets its own copy of the `moon` array (no shared reference). Returns `{ forecastStart, timezone, hours }`.
- `timeBoundary.js` — the locale/time sibling of the adapter. `tagLocalDays(hours, forecastStart, timezone)` tags each hour with an internal `localDay` key (the forecast location's calendar day) **and an internal `localHour` key** (0–23 in that zone) computed from the UTC instant via `Intl` with an explicit `timeZone`; both are internal and never reach the wire (`localHour` drives the time-of-day window filter and the night-stitch). Also exports `localHour` and `zonedWallTimeToUtcIso` — the latter converts the provider's local wall-time (returned under `timezone=auto`) to a UTC-`Z` instant.
- `adapters/meteosource.js` — extracts provider-specific fields. Returns `null` (via `?? null`) for absent `wind.speed`, `precipitation.total`, and `cloud_cover.total` rather than letting `undefined` propagate. Defaults `uv_index ?? 0` (Meteosource returns `null` at night; nighttime UV genuinely is 0, so unlike the nullable trio a `0` is a true reading and keeps `uV` non-null on the wire — this fixed the live decode bug found on 2026-07-12). Extracts the top-level `timezone`; converts the provider's local wall-time `forecastStart` to UTC-`Z` via that zone (`timezone=auto` returns local timestamps, so a blind `Z`-append would be wrong). Swap this file to change weather provider without touching parse logic.
- `UpstreamError.js` — typed `Error` subclass (`name: 'UpstreamError'`) used to mark any provider-side failure (network, non-OK status, malformed payload, empty data). Route layer uses `instanceof` to map it to `502`.

### `src/decision/`
- `index.js` — public. Re-exports `evaluateAll`.
- `evaluateAll.js` — `evaluateAll(hours, activities)` over the **caller-supplied** activities. Bucketing happens **per activity** (inside the loop, not once outside) because the strategy depends on the activity's optional `window` (`bucketsForActivity`): no window → one bucket per `localDay`; same-day window (`startHour < endHour`) → calendar-day buckets filtered to `localHour ∈ [startHour, endHour)`; wrapped window (`startHour > endHour`) → **night-stitch** (`bucketNightWindow`) that pairs each evening with the next morning, drops the pre-horizon orphan morning, and indexes by the evening's day. Every bucket carries its global offset, so `evaluate()`'s slice-relative window is offset back to **global `hours[]` indices**. Result field order: `activityId`, `label`, `displayMetrics`, `days[]`; each day is `{ dayIndex, rating, (startIndex, endIndex, duration) }`. **Seam:** `hours` must be pre-tagged with `localDay`/`localHour` (the route passes tagged hours); untagged hours collapse to one bucket silently.
- `decision_engine.js` — core logic: `evaluateHour`, `findLongestWindow`, `evaluate`. Reused **unchanged** — `evaluateAll` calls `evaluate()` over each bucket's hour-slice. `checkThreshold` treats `null`/`undefined` values as failing the threshold (absent data fails rather than silently passing via NaN coercion). `findLongestWindow` uses strict `>` for tie-breaking, so on equal durations the earlier window wins. Do not import this directly from outside the module.

---

## Activity object shape (request body)

Activities are **caller-supplied** ([ADR-0005](docs/adr/0005-custom-activity-request-schema.md)) — the engine holds no list. Each activity in the request `activities[]` must have:

```js
{
  id:             "client-stable-string", // unique within the request; echoed as activityId
  label:          "Human Label",
  displayMetrics: ["temp", "windSpeed"],  // ordered render superset; thresholds.keys ⊆ this
  thresholds: {
    temp:      { min: 15, max: 35, required: true  },
    windSpeed: {          max: 15, required: false },
    dustAlert: { type: "flag", forbidTrue: true, required: true },
  },
  window: { startHour: 22, endHour: 2 },  // OPTIONAL local-hour window; wrap = nocturnal
}
```

Threshold rules:
- Numeric fields: `min`, `max`, `required` — omit whichever bound is unconstrained (but at least one bound is mandatory).
- Boolean fields: `type: "flag"`, `forbidTrue: true` — fails the hour when the field is `true`.
- `required: true` → failing makes the hour **Bad**. `required: false` → failing makes it **Good** instead of **Perfect**. `required` is mandatory on every threshold.
- Only **live** metrics may be thresholded or displayed; a coming-soon/unknown metric is a hard `400` (see metric catalog).

The shape is enforced at the route boundary by `validateRatingRequest`; the engine assumes a valid body.

---

## Pending / placeholder data

Several hourly fields are hardcoded in `parse.js` pending real data sources. These are the **coming-soon** metrics in `metricCatalog.js`: because a threshold against placeholder data would pass trivially (a silent false **Perfect**), `validateRatingRequest` **hard-rejects** any request that thresholds *or* displays one of them (`400`). They still appear in the `hours[]` wire shape as placeholders for the timeline. Each becomes live (and request-usable) when its adapter lands:

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
- `tests/decision/evaluateAll.test.js` — multi-activity evaluation over **caller-supplied** activities; verifies one result per activity in request order, per-activity `days[]` shape, dense contiguous `dayIndex`, the null-day convention, that per-day window indices are **global** (a qualifying window on day ≥1 catches a missing per-day offset), and the time-of-day window paths: same-day `[startHour,endHour)` filtering (in- vs out-of-window failures), the wrapped **night-stitch** (hand-verified global indices across midnight), per-activity `days.length` (diurnal vs nocturnal in one call), and the dropped orphan morning.
- `tests/weather/metricCatalog.test.js` — pins the live vs coming-soon metric sets, disjointness, and `isKnown`/`isAvailable`.
- `tests/routes/validateRatingRequest.test.js` — the full ADR-0005 §6 rejection set (lat/lon range, activities array + abuse ceiling, id/label, displayMetrics, subset invariant, unknown/coming-soon metrics in both lists, numeric `min>max`/bound-less, missing `required`, `requireTrue`, window hour bounds + `startHour===endHour`) plus the atomic-collect/structured-shape contract and valid happy cases (wrapped window, flag, show-but-don't-judge).
- `tests/weather/timeBoundary.test.js` — unit tests for the time-boundary module. Tags hours with `localDay` **and `localHour`** against the ADR-0003 worked example (164 hours from `2026-06-19T12:00:00Z`, `Asia/Dubai` → 8 buckets of 8/24×6/12); the UTC-instant landmine guard (host timezone must not shift buckets); and `zonedWallTimeToUtcIso` (local wall-time → UTC-`Z`, no millis, idempotent on already-zoned input).
- `tests/weather/adapter.test.js` — unit tests for the Meteosource adapter. Per-field coverage: `windSpeed`/`rainFall`/`cloudCover` returning `null` when the upstream payload omits the source field; the `timezone` extractor; `forecastStart` converting the provider's local wall-time to UTC-`Z` via the zone (idempotent on already-UTC-`Z`).
- `tests/weather/parse.test.js` — unit tests for `parseWeather`. Covers the 168-hour ceiling slice (and pass-through of a smaller provider count), `timezone` passthrough, the `UpstreamError` on empty hourly data, per-hour `moon` array isolation, placeholder defaults, and a contract pin on the per-hour key order (no `hour`).
- `tests/weather/fetch.test.js` — unit tests for `fetchWeather`. Wraps network failures and non-OK responses as `UpstreamError`.
- `tests/weather/getWeather.test.js` — unit tests for the public `getWeather`. Includes the `API_KEY` guard, confirmation that it sends `timezone=auto` and targets the `flexi` endpoint, and that it surfaces `timezone` plus an internal `localDay` per hour.
- `tests/server/health.test.js` — 1 test: `GET /health` returns `200` with `status: ok`.
- `tests/server/rating.test.js` — integration tests for the `POST` route. Uses the `createRatingRouter({ getWeather, evaluateAll })` factory to inject fakes — no live API calls and no `require.cache` patching. Covers body-validation 400s (structured `errors[]`, atomic rejection, **validation-before-getWeather**), the day-bucketed response shape (top-level `timezone` + per-hour `index` with `localDay`/`localHour` stripped and `hour` dropped + per-activity `days[]` echoing the request), the null-day wire convention, a partial-day-0 fixture (variable-length buckets + non-24 global offset), a **nocturnal night-stitch** fixture (per-activity `days.length` at the wire), the uniform `{ errors }` envelope on `UpstreamError → 502` and generic `Error → 500`, and the ignored stray `timezone` body field. Includes a golden snapshot test pinning the full response shape, request-order activity array, per-object key order, and global window indices against the documented contract.

---

## Running the server

```
npm run dev        # nodemon — auto-restarts on file save (development)
npm start          # node app.js (production)
```

`GET /health` — liveness check (used by Railway).
`POST /api/v1/rating` — body `{ lat, lon, activities[] }`; returns the 7-day forecast + per-day ratings for the supplied activities. Example:

```
curl -X POST localhost:3000/api/v1/rating -H 'Content-Type: application/json' \
  -d '{"lat":25.1627,"lon":55.2077,"activities":[{"id":"vb","label":"Volleyball","displayMetrics":["temp"],"thresholds":{"temp":{"min":15,"max":35,"required":true}}}]}'
```

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

- **Done:** Issue #3 (backend internals), Issue #4 (HTTP API — Express server), Issue #10 (pre-5a hardening — typed provider errors, null-safe adapter, DI factory router, expanded test coverage). **Rebuild Phase 1** (7-day day-bucketed `days[]`/`timezone` output). **Rebuild Phase 2** (`GET→POST` request flip, caller-supplied `evaluateAll(hours, activities)`, ADR-0005 validation + metric catalog, wrap-gated night-stitch, curated `src/activities/` removed). **Issue #5a** (core iOS SwiftUI app — built, live-verified, independently audited + merged to `main` 2026-07-12). **Issue #5b** (iOS personalization — client-side activity authoring add/edit/delete from Template or scratch, `ActivityStore` local persistence seeded with the two #5a Templates, static metric catalog behind the `MetricCatalogProviding` swap seam, client-side ADR-0005 validation mirror, optional time-of-day window incl. nocturnal wrap + "Tonight" labels, home-location picker, soft quantity cap — no StoreKit/Pro, no cloud sync; iOS 138 tests)
- **Next:** Issue #6 (deploy + APNs — note #6a accounts/auth is CUT per ADR-0001; only #6b Railway deploy + #6c device-keyed push remain)
- **Parallel:** Issue #7 (marine data), Issue #8 (`requireTrue` flag type)
