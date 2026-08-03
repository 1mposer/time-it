# time-it — codebase guide

Domain language is defined in [`docs/CONTEXT.md`](docs/CONTEXT.md). Read it before touching any logic. The terms **Pursuit**, **Activity**, **Threshold**, **Rating**, **Window**, **Index**, **Forecast start**, **Lite/Pro**, and **Display metrics** have precise meanings there.

Then, **before assuming any contract**, read [`docs/STATUS.md`](docs/STATUS.md) for the current project status — which terms/contracts describe code-as-it-exists vs locked-but-unbuilt design, and what is currently blocked. Order: **CLAUDE.md → CONTEXT.md (learn the terms) → STATUS.md (current status)**.

Vendor/provider API specifics — request params, response schema, known field behavior, rate limits/refresh cadence — live in `docs/API_documentation/<provider>/` (one directory per adapter: a trimmed `README.md` for agent lookup + the raw vendor export). Not part of the read order above, but check there **before** asking a question about a specific weather provider's behavior — it exists precisely so that question doesn't need re-deriving. Currently: [`docs/API_documentation/meteosource/README.md`](docs/API_documentation/meteosource/README.md).

---

## What the system does

Accepts a `POST` with a `lat`/`lon` and a list of **caller-supplied Activities** (each with a **Threshold** profile and an optional time-of-day **Window**), fetches a 7-day rolling weather **Forecast** (hourly, up to 168 entries) for that location, evaluates the forecast against every Activity, and returns a per-local-calendar-day **Rating** (the best **Window** found within each day) for each. The engine holds **no** activity list — activities are authored client-side and sent in the request body ([ADR-0002](docs/adr/0002-activity-agnostic-engine.md), [ADR-0005](docs/adr/0005-custom-activity-request-schema.md)). Output is consumed by an iOS app (Issue #5) and by the server-side **push path** ([ADR-0006](docs/adr/0006-device-keyed-push-evaluation.md)): opted-in devices upsert an anonymous **Device snapshot** (`PUT /api/v1/devices/:deviceId`), and an in-process hourly cron evaluates each snapshot with the same engine to send the daily **Digest** (Issue #6c) and the event-driven **Perfect-window alert** (Issue #6d — bucket-keyed dedup via `notification_state`). Both push jobs' backends are built; the iOS opt-in client is still to come.

---

## Architecture — HTTP server + three deep modules

Callers import only the public surface of each module. Internal files (`fetch.js`, `parse.js`, `decision_engine.js`, individual activity files) are implementation details.

```
app.js                          →  entry point. initDb() → app.listen(PORT, '0.0.0.0') → startJobs(); exits non-zero if initDb fails
src/server.js                   →  Express app (exported, no .listen). CORS, express.json(), health route, mounts routers
src/routes/rating.js            →  createRatingRouter({ getWeather, evaluateAll })  →  POST /api/v1/rating
src/routes/devices.js           →  createDevicesRouter({ getWeather, db })  →  PUT/DELETE /api/v1/devices/:deviceId
src/routes/validateRatingRequest.js →  validateRatingRequest(body)  returns structured error[] (ADR-0005 §6)
src/routes/validateActivities.js    →  validateActivities(activities, pathPrefix)  shared per-activity rules (rating + devices)
src/routes/errorEnvelope.js         →  errorBody / sendRouteError    shared { errors } envelope + 502/500 mapping

src/weather/index.js         →  getWeather(lat, lon)             returns { forecastStart, timezone, hours }
src/weather/metricCatalog.js →  LIVE/COMING_SOON metric sets     isKnown / isAvailable (validation source of truth)
src/weather/UpstreamError.js →  UpstreamError                     typed provider-failure error
src/decision/index.js        →  evaluateAll(hours, activities)    returns Activity result[] (per-activity days[])

src/services/weatherCache.js →  getCachedWeather(lat, lon)        shared 60-min in-memory cache over getWeather
src/db.js                    →  query / initDb                    lazy pg pool + idempotent devices/notification_state schema (push path only)
src/notifications/apns.js    →  sendPush / StaleTokenError        APNs seam (apns2 imported nowhere else)
src/jobs/index.js            →  startJobs()                       in-process node-cron, hourly digest + detector passes (single replica)
src/jobs/dailyDigest.js      →  createDailyDigestJob({ db, getWeather, evaluateAll, sendPush, now })
src/jobs/perfectWindowDetector.js →  createPerfectWindowDetectorJob({ db, getWeather, evaluateAll, sendPush, now })
src/jobs/labels.js           →  hourLabel / rangeLabel            clock-label copy shared by both push jobs
```

There is **no** `src/activities/` module — activities are caller-supplied in the request body (deleted in Phase 2; the curated list moves to client-side Templates per [ADR-0002](docs/adr/0002-activity-agnostic-engine.md)).

The full data flow is two steps (the route validates the body first, then):

```js
const { forecastStart, timezone, hours } = await getWeather(lat, lon);
const results = evaluateAll(hours, activities); // activities come from the POST body
```

In production `getWeather` is the **shared 60-min weather cache** (`getCachedWeather` in `src/services/weatherCache.js`, keyed on lat/lon at 2 dp) — the same instance serves `/rating`, the device upsert's timezone resolution, and the push jobs (#6c spec §6, amended 2026-07-20). The response contract is unchanged; only the provider fetch is memoized.

`forecastStart` is an ISO 8601 UTC timestamp with a `Z` suffix (e.g. `"2026-06-10T14:00:00Z"`). `timezone` is the **forecast location's** IANA zone (e.g. `"Asia/Dubai"`). The iOS app combines `forecastStart` + `timezone` + each hourly **Index** to render local clock times and day labels in the *location's* zone — so they match the server's day bucketing (see [ADR-0004](docs/adr/0004-day-bucketed-rating-wire-shape.md)). The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode `forecastStart` without custom formatting.

Internally, `getWeather` tags each hour with a `localDay` key (the location's calendar day) and a `localHour` key (0–23 in the location's zone) via the **time-boundary module** so `evaluateAll` can bucket results by day and filter/stitch time-of-day **Windows**; both `localDay` and `localHour` are internal and stripped before the wire.

---

## API response contract

The HTTP API has four routes: the two below plus the push-path device routes (`PUT`/`DELETE /api/v1/devices/:deviceId` — see [Push path](#push-path--device-registration-daily-digest-perfect-window-detector-issues-6c6d)). Treat the shapes below as the contract — the iOS client (Issue #5a) decodes against them.

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

## Push path — device registration, daily digest, Perfect-window detector (Issues #6c/#6d)

Server-side per-device state exists **only** here ([ADR-0006](docs/adr/0006-device-keyed-push-evaluation.md)) — the `/rating` path stays stateless. Postgres holds one `devices` row per opted-in install (`device_id` = client-minted Keychain UUID, `apns_token`, `home_lat`/`home_lon`, server-resolved IANA `timezone`, `activities` JSONB, `last_digest_date`, `updated_at`) plus the detector's `notification_state` dedup ledger (`(device_id, activity_id, bucket_date)` PK, `ON DELETE CASCADE` with its device row); `initDb()` is an idempotent `CREATE TABLE IF NOT EXISTS` pair (no migration framework). Jobs are in-process `node-cron` on the always-on **single-replica** web service (2+ replicas duplicate pushes).

### `PUT /api/v1/devices/:deviceId`

Full-snapshot upsert — client-authoritative, last-write-wins, re-sent on any change (activity edit, home change, token refresh). Body `{ "apnsToken": "<hex>", "home": { "lat", "lon" }, "activities": [...] }`. The `activities` are validated with the **same shared rules as the rating body** (`validateActivities`) with one deliberate divergence: an **empty `[]` is valid** — a dormant snapshot (deleting the last Activity must not strand the stale one). The location's IANA zone is resolved server-side through the shared weather cache (one, usually cached, provider call — also proving the location is servable). Success → `204` (no body); `last_digest_date` is **preserved** across upserts. Errors use the uniform `{ errors }` envelope: `400` validation, `502` provider failure, `500` otherwise. No auth — the deviceId is an unguessable UUID (accepted risk, ADR-0001).

### `DELETE /api/v1/devices/:deviceId`

Opt-out. Deletes the row; `204` even when the row doesn't exist (idempotent).

### Daily digest job (`src/jobs/dailyDigest.js`)

Hourly cron pass (`0 * * * *`, started after `listen`). Per device: fires when the device-local hour is in the **6..11 catch-up band** (not `=== 6` — a redeploy across the 6am tick must not drop a timezone band's digest; past noon, skip) and `last_digest_date` < device-local today — **at most one push per device per day**, sent **only when something qualifies**. Content: today/tonight line per Activity from `days[0]` (`"Cycling: Perfect 7–10am"`; a nocturnal Activity reads `"… tonight 10pm–2am"` — detected from the *snapshot's* `window`, which results never echo), plus week-ahead **Perfect** highlights over buckets `2..days.length−1` (per-activity length — never a hardcoded `2–6`; bucket 1 belongs to the #6d detector). A `StaleTokenError` from the APNs seam deletes the device row. All local-day/hour math goes through `timeBoundary.js`; the pg `DATE`-as-JS-`Date` marker is normalised to `'YYYY-MM-DD'` before comparison (the §7 type trap — `dateObject < 'string'` is always false in JS).

### Perfect-window detector job (`src/jobs/perfectWindowDetector.js`, Issue #6d)

The event twin of the digest, on the same hourly tick: push the moment a **new Perfect** window appears in buckets **0–1** (~48h; far-out days are volatile, there is no retraction push — they surface via the digest's week-ahead line). **Perfect-only** — Good belongs to the digest; a good→perfect upgrade alerts inherently as that bucket's first Perfect. Dedup: **at most one alert per `(device_id, activity_id, bucket_date)`** where `bucket_date` comes from `timeBoundary.bucketDate(forecastStart, timezone, dayIndex)` — **never** from window indices (they re-base against every fresh `forecastStart`; the pre-rebuild `startIndex` dedup re-alerted hourly) and **never** from `hours[startIndex].localDay` (a nocturnal morning-tail window carries the *morning's* date, which would both re-alert on cross-midnight jitter and suppress the real next-night alert). The insert (`ON CONFLICT DO NOTHING`) happens **before** the push and the push is sent only when the row was actually inserted — a crash between the two makes a missed alert, never a duplicate. An already-**ended** window (`forecastStart + endIndex` hours ≤ now — `endIndex` is exclusive) is skipped before the insert; an **ongoing** one alerts as `"Now until 6pm"`. Copy otherwise: title `Perfect Cycling window`, body `"Today 7–10am (3h)"` / `"Tomorrow …"` (nocturnal, from the snapshot's `window`: `"Tonight …"` / `"Tomorrow night …"`); payload `{ type: 'perfectWindow', activityId, bucketDate }`. `StaleTokenError` deletes the device row (state rows cascade). Each pass ends by pruning `notification_state` rows with `bucket_date < today − 2 days`, so the table stays O(devices × activities × 2).

---

## Module internals

### `src/routes/`
- `rating.js` — exports `createRatingRouter({ getWeather, evaluateAll })` factory. Mounts `POST /api/v1/rating` on a fresh Express router. **Validates the JSON body via `validateRatingRequest` BEFORE calling `getWeather`** (a malformed request spends no provider call); on any error returns `400` with the structured `{ errors }` array. Otherwise calls injected `getWeather(lat, lon)` and `evaluateAll(hours, activities)`, then shapes the wire JSON: strips the internal `localDay`/`localHour` from each hour, prepends `index`, and assembles `{ forecastStart, timezone, activities, hours }`. Error mapping via the shared `errorEnvelope.js` (all bodies are the uniform `{ errors }` envelope): `400` (validation), `502` (`err instanceof UpstreamError` — provider failure), `500` (any other thrown error). Default dependencies resolve to the real modules — but the **production wiring in `server.js` injects `getCachedWeather`** (the shared 60-min cache) instead of the raw `getWeather`; tests pass fakes via the factory arg.
- `devices.js` — exports `createDevicesRouter({ getWeather, db })` factory (defaults: the shared weather cache + `src/db.js`). `PUT /api/v1/devices/:deviceId` (full-snapshot upsert, empty-`[]` valid, timezone resolved server-side, `last_digest_date` preserved) and idempotent `DELETE`. See the [Push path](#push-path--device-registration-daily-digest-perfect-window-detector-issues-6c6d) section for the contract.
- `validateRatingRequest.js` — exports `validateRatingRequest(body)` → array of `{ path, message }` (empty = valid). Atomic (collects every failure across the whole body, never first-wins) and structured per [ADR-0005 §6](docs/adr/0005-custom-activity-request-schema.md). Owns the rating-only rules (lat/lon range, **non-empty** activities); the per-activity rules live in the shared `validateActivities.js`. The route maps a non-empty result to a single `400`.
- `validateActivities.js` — exports `validateActivities(activities, pathPrefix = 'activities')`, the per-activity ADR-0005 rule block shared by the rating and devices routes (extracted for #6c — same messages, same relative paths; the rating route's output is byte-identical to pre-extraction). Owns the per-request duplicate-`id` set and the ~50 abuse ceiling; the non-empty rule stays with each caller (an empty device snapshot is valid, an empty rating request is not). Imports the metric catalog to hard-reject unknown/coming-soon metrics in either `displayMetrics` or `thresholds` (the false-Perfect backstop).
- `errorEnvelope.js` — exports `errorBody(message, path?)` and `sendRouteError(res, err)` (the shared `UpstreamError → 502` / other → `500` catch mapping) so the `{ errors }` envelope never forks across routers. (The malformed-JSON `400`/`413` middleware in `server.js` is the other shared piece — any mounted router inherits it.)

### `src/weather/`
- `index.js` — public. Guards `process.env.API_KEY` (throws plain `Error` if missing), then fetch → parse → tags each hour with its `localDay` **and `localHour`** (via the time-boundary module) → returns `{ forecastStart, timezone, hours }`. Sends `timezone: 'auto'` in the upstream request — the only Meteosource mode that exposes the location IANA zone — and does not accept a timezone arg. Owns the Meteosource adapter selection and all API params.
- `metricCatalog.js` — the server-side source of truth for which metrics exist and which carry **live** data vs a **coming-soon** placeholder (`LIVE_METRICS`, `COMING_SOON_METRICS`, `isKnown`, `isAvailable`). `validateRatingRequest` imports it to hard-reject a threshold/display on a non-live metric (the false-Perfect guard). Kept separate so the deferred `GET /api/v1/metrics` catalog route (future ADR — 0006 is the push ADR) can read the same source.
- `fetch.js` — calls the Meteosource `flexi` REST endpoint (`/api/v1/flexi/point`, the 7-day tier; `/free/` caps at 24h). Wraps non-OK responses and network errors as `UpstreamError` so the route layer can map them to `502`.
- `parse.js` — normalises raw response to the unified hourly schema, capped at the `FORECAST_HOURS` ceiling (168) — fewer passes through; never fabricates hours. Throws `UpstreamError` if the provider returns no hourly data. Each hour gets its own copy of the `moon` array (no shared reference). Returns `{ forecastStart, timezone, hours }`.
- `timeBoundary.js` — the locale/time sibling of the adapter. `tagLocalDays(hours, forecastStart, timezone)` tags each hour with an internal `localDay` key (the forecast location's calendar day) **and an internal `localHour` key** (0–23 in that zone) computed from the UTC instant via `Intl` with an explicit `timeZone`; both are internal and never reach the wire (`localHour` drives the time-of-day window filter and the night-stitch). Also exports `localDay`, `localHour`, `zonedWallTimeToUtcIso` (converts the provider's local wall-time returned under `timezone=auto` to a UTC-`Z` instant), and `bucketDate(forecastStart, timezone, dayIndex)` — the calendar date a bucket's `dayIndex` refers to (date-of-day-0 + dayIndex), shared by the #6c digest's weekday labels and #6d's `bucket_date` dedup key. The digest job's selection/marker logic runs on `localHour`/`localDay` — do not hand-roll `Intl` calls.
- `adapters/meteosource.js` — extracts provider-specific fields. Returns `null` (via `?? null`) for absent `wind.speed`, `precipitation.total`, and `cloud_cover.total` rather than letting `undefined` propagate. Defaults `uv_index ?? 0` (Meteosource returns `null` at night; nighttime UV genuinely is 0, so unlike the nullable trio a `0` is a true reading and keeps `uV` non-null on the wire — this fixed the live decode bug found on 2026-07-12). Extracts the top-level `timezone`; converts the provider's local wall-time `forecastStart` to UTC-`Z` via that zone (`timezone=auto` returns local timestamps, so a blind `Z`-append would be wrong). Swap this file to change weather provider without touching parse logic. Vendor API reference (endpoints, params, schema, refresh cadence) lives beside — not inside — the code: [`docs/API_documentation/meteosource/README.md`](docs/API_documentation/meteosource/README.md).
- `UpstreamError.js` — typed `Error` subclass (`name: 'UpstreamError'`) used to mark any provider-side failure (network, non-OK status, malformed payload, empty data). Route layer uses `instanceof` to map it to `502`.

### `src/decision/`
- `index.js` — public. Re-exports `evaluateAll`.
- `evaluateAll.js` — `evaluateAll(hours, activities)` over the **caller-supplied** activities. Bucketing happens **per activity** (inside the loop, not once outside) because the strategy depends on the activity's optional `window` (`bucketsForActivity`): no window → one bucket per `localDay`; same-day window (`startHour < endHour`) → calendar-day buckets filtered to `localHour ∈ [startHour, endHour)`; wrapped window (`startHour > endHour`) → **night-stitch** (`bucketNightWindow`) that pairs each evening with the next morning, drops the pre-horizon orphan morning, and indexes by the evening's day. Every bucket carries its global offset, so `evaluate()`'s slice-relative window is offset back to **global `hours[]` indices**. Result field order: `activityId`, `label`, `displayMetrics`, `days[]`; each day is `{ dayIndex, rating, (startIndex, endIndex, duration) }`. **Seam:** `hours` must be pre-tagged with `localDay`/`localHour` (the route passes tagged hours); untagged hours collapse to one bucket silently.
- `decision_engine.js` — core logic: `evaluateHour`, `findLongestWindow`, `evaluate`. Reused **unchanged** — `evaluateAll` calls `evaluate()` over each bucket's hour-slice. `checkThreshold` treats `null`/`undefined` values as failing the threshold (absent data fails rather than silently passing via NaN coercion). `findLongestWindow` uses strict `>` for tie-breaking, so on equal durations the earlier window wins. Do not import this directly from outside the module.

### `src/services/`
- `weatherCache.js` — the shared in-memory weather cache (#6c spec §6). `createWeatherCache({ getWeather, ttlMs, now })` factory for tests + the production singleton `getCachedWeather`. Key = lat/lon at 2 dp (~1.1 km — nearby devices share entries), **60-min TTL** (owner-confirmed Meteosource upstream cadence — [`docs/API_documentation/meteosource/README.md`](docs/API_documentation/meteosource/README.md)). Caches the **promise** so concurrent callers share one in-flight fetch; a rejected fetch is evicted immediately. One instance for every consumer (`/rating`, device upsert, jobs) — do not build a second cache.

### `src/db.js`
- Lazy `pg` pool over `DATABASE_URL` (requiring the module never opens a connection — only the first query does), `query` passthrough, idempotent `initDb()` creating the `devices` and `notification_state` tables (the latter cascades away with its device row). The push path's only state; `/rating` and `GET /health` never touch it.

### `src/notifications/`
- `apns.js` — the APNs seam; `apns2` is imported nowhere else (provider-specifics stop at the boundary). `createPushSender({ transport })` for tests + the production `sendPush(apnsToken, { title, body, payload })`; the real transport is built lazily from env on first send (`buildApnsConfig`: `APNS_KEY` = `.p8` PEM **content**, `\n`-escape tolerant; `APNS_KEY_ID`; `APNS_TEAM_ID`; topic from optional `APNS_TOPIC`, defaulting to **`com.timeit.app.dev`** — the topic must equal the installed app's bundle ID, and the un-suffixed `com.timeit.app` belongs to another Apple account (2026-08-03; the Xcode project's `PRODUCT_BUNDLE_IDENTIFIER` still needs the matching rename); sandbox host unless `NODE_ENV === 'production'`). APNs `Unregistered`/`BadDeviceToken` → typed `StaleTokenError` so callers delete the device row.

### `src/jobs/`
- `index.js` — `startJobs()`: `node-cron` `0 * * * *` wiring both push jobs to the production dependencies (shared cache, real db, APNs singleton). One tick runs the digest pass then the detector pass sequentially, each with its own catch (a digest wipeout never skips the detector) — sharing the 60-min weather cache means both passes cost one provider call per location. Called by `app.js` **after** `listen`, on the single always-on replica.
- `dailyDigest.js` — `createDailyDigestJob({ db, getWeather, evaluateAll, sendPush, now })` → `runDigestPass()`. Selection, dedup, composition, and stale-token handling as described in the [Push path](#push-path--device-registration-daily-digest-perfect-window-detector-issues-6c6d) section; per-device try/catch so one failure never stops a pass.
- `perfectWindowDetector.js` — `createPerfectWindowDetectorJob({ db, getWeather, evaluateAll, sendPush, now })` → `runDetectorPass()`. Bucket-keyed dedup (insert-first `ON CONFLICT DO NOTHING`, push only on actual insert), buckets 0–1, ended-window skip **before** the insert, end-of-pass pruning — see the Push path section for the full contract. `bucket_date` derivation goes through `timeBoundary.bucketDate` only.
- `labels.js` — `hourLabel`/`rangeLabel`, the clock-label copy shared by both jobs (the server-side twin of the iOS `TimeDeriver`). Known cosmetic limitation: half-hour zones (e.g. Asia/Kolkata +05:30) render the `ha`-style labels :30 off (STATUS §5).

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
- `tests/routes/validateRatingRequest.test.js` — the full ADR-0005 §6 rejection set (lat/lon range, activities array + abuse ceiling, id/label, displayMetrics, subset invariant, unknown/coming-soon metrics in both lists, numeric `min>max`/bound-less, missing `required`, `requireTrue`, window hour bounds + `startHour===endHour`) plus the atomic-collect/structured-shape contract and valid happy cases (wrapped window, flag, show-but-don't-judge). Unchanged by the #6c `validateActivities` extraction — it doubles as the refactor's tripwire.
- `tests/routes/devices.test.js` — DI-fake tests for the device routes (stateful fake db in the pg row shape): upsert happy path (204, row shape, server-resolved timezone), **empty-`[]` upsert → 204** (dormant snapshot), last-write-wins with `last_digest_date` preserved, validation 400s incl. the shared-rule paths/messages, validation-before-provider, `502` on provider failure, DELETE idempotency.
- `tests/services/weatherCache.test.js` — TTL expiry with a fake clock, 2-dp key sharing/splitting, concurrent in-flight dedupe, rejected-fetch eviction.
- `tests/server/ratingCache.test.js` — `/rating` composed with a real cache around a spy provider: two identical POSTs = one provider call, identical bodies; plus a structural pin that `server.js` wires `getCachedWeather` in.
- `tests/notifications/apns.test.js` — seam contract with a stubbed transport (`Unregistered`/`BadDeviceToken` → `StaleTokenError`, other errors rethrown) and the pure env→config mapping (topic, host by `NODE_ENV`, `\n` normalisation, missing-var throws).
- `tests/jobs/dailyDigest.test.js` — fake clock/db/weather/apns: cross-zone 6am selection (Dubai vs Toronto fire on different passes), catch-up band (7–11 delivers once; past noon skips), sent-today suppression **with the fake db returning a real `Date` object** (the pg driver shape — pins the §7 type trap), per-device error isolation, dormant-`[]` snapshot, no-qualifying → no push + marker untouched, copy composition (diurnal `7–10am`, nocturnal `tonight 10pm–2am` from the snapshot's window, Good, combined sections, 8-bucket tail-day Perfect appears, 6-bucket nocturnal never over-indexes, bucket 1 never surfaces), `StaleTokenError` → row deleted.
- `tests/jobs/perfectWindowDetector.test.js` — fake clock/apns + a **stateful** fake db (the `notification_state` set survives across passes, so re-run tests exercise real dedup semantics). Covers: first Perfect → one push + one state row; same-forecast re-run → nothing; the **re-based `forecastStart` regression** (the old `startIndex`-dedup bug — same real-world window, shifted indices, no re-alert); Good-only → nothing + no key consumed, later upgrade → push; buckets 0+1 both alert, bucket 2 never; ended window skipped before the insert (exact-boundary `endIndex` exclusivity pinned); ongoing → `"Now until 10am"`; nocturnal evening-keyed `bucket_date` + `"Tonight"` copy; the **morning-tail trap** (a Perfect window entirely after midnight keys on the evening's date; cross-midnight jitter neither re-alerts nor consumes the next night's key); two activities → independent rows; insert-conflict race → no duplicate push; pruning (strict `<` today − 2); `StaleTokenError` → device row deleted mid-pass; per-device isolation; dormant-`[]` snapshot.
- `tests/weather/timeBoundary.test.js` — unit tests for the time-boundary module. Tags hours with `localDay` **and `localHour`** against the ADR-0003 worked example (164 hours from `2026-06-19T12:00:00Z`, `Asia/Dubai` → 8 buckets of 8/24×6/12); the UTC-instant landmine guard (host timezone must not shift buckets); `zonedWallTimeToUtcIso` (local wall-time → UTC-`Z`, no millis, idempotent on already-zoned input); and `bucketDate` (date-of-day-0 + dayIndex, month/year rollover).
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

`GET /health` — liveness check (used by Railway; deliberately DB-independent).
`POST /api/v1/rating` — body `{ lat, lon, activities[] }`; returns the 7-day forecast + per-day ratings for the supplied activities.
`PUT`/`DELETE /api/v1/devices/:deviceId` — push-path snapshot registration/opt-out (see the Push path section). Example:

```
curl -X POST localhost:3000/api/v1/rating -H 'Content-Type: application/json' \
  -d '{"lat":25.1627,"lon":55.2077,"activities":[{"id":"vb","label":"Volleyball","displayMetrics":["temp"],"thresholds":{"temp":{"min":15,"max":35,"required":true}}}]}'
```

Requires `.env` with `API_KEY=<meteosource key>`, **`DATABASE_URL=<postgres>`** (since #6c, `app.js` runs `initDb()` before `listen` and exits non-zero if it fails — local dev needs a reachable Postgres), and optionally `PORT=3000`. The APNs vars (`APNS_KEY` PEM content, `APNS_KEY_ID`, `APNS_TEAM_ID`) are needed only when a push is actually sent — the seam builds its client lazily on first send. See `.env.example`.

## CLI (development only)

`cli.js` at the root hits the live Meteosource API and prints a single-activity evaluation as JSON:

```
node cli.js | python3 -m json.tool
```

Requires `.env` with `API_KEY=<meteosource key>`.

---

## Current build order

See [`docs/issues/ROADMAP.md`](docs/issues/ROADMAP.md) for the full critical path.

- **Done:** #3 backend internals · #4 HTTP API · #10 pre-5a hardening · Rebuild Phases 1+2 (day-bucketed `days[]`/`timezone` output; `GET→POST` caller-supplied activities, ADR-0005 validation, night-stitch, curated `src/activities/` removed) · **#5a core iOS app** (merged 2026-07-12) · **#5b iOS authoring/personalization** (built 2026-07-13) · **[#6b Railway deploy](docs/issues/completed/implement-spec-issue-6b-railway-deploy.md)** (complete 2026-07-20, stateless, no DB) · **[#5c location onboarding](docs/issues/completed/implement-spec-issue-5c-location-onboarding.md)** (complete 2026-08-01 — worldwide; Dubai fallback deleted; Active-location chain → grayed empty state; CTA-gated permission prompt; MapKit city picker). Per-issue status: [ROADMAP](docs/issues/ROADMAP.md); current state + handoff notes: [STATUS §5](docs/STATUS.md).
- **In progress:** **[#6c device registration + daily digest](docs/issues/current/implement-spec-issue-6c-registration-and-digest.md)** — **backend built 2026-08-01, merged to `main`**: Postgres `devices` schema + `initDb`, snapshot upsert/delete routes, shared `validateActivities`/error-envelope extractions, shared 60-min weather cache (now also serving `/rating`), `apns2` seam, hourly digest job. **[#6d Perfect-window detector](docs/issues/current/implement-spec-issue-6d-perfect-window-detector.md)** — **backend built 2026-08-01** (branch `issue-6d-perfect-window-detector`): `notification_state` dedup table, hourly detector job (Perfect-only, buckets 0–1, bucket-date dedup, insert-first push), wired beside the digest. **Remaining for both:** owner's Railway/APNs manual steps, live acceptance checks, and the iOS §9 opt-in/registration client (deferred — needs the APNs entitlement and the pbxproj currently in flight with the WeatherKit track); see the handoffs in `docs/issues/current/`.
- **Next:** owner manual steps + iOS push opt-in client. #6a accounts/auth is CUT per ADR-0001.
- **Parallel:** Issue #7 (marine data), Issue #8 (`requireTrue` flag type)
