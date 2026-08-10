# Handoff — Abstracting fetch/auth for an additional weather provider (Apple WeatherKit)

> ⏸️ **DEFERRED post-ship (owner decision 2026-08-10).** WeatherKit is a later project. The "in-flight track" working-tree edits were discarded 2026-08-10 (they contained no WeatherKit work — only Xcode churn). This analysis is preserved as the input to a future provider-descriptor ADR; do not implement from it without that ADR.

**Status:** exploratory findings + recommendation. Not a locked spec — no ADR yet.
**Date:** 2026-07-30
**Scope:** what exists today, what's missing, and how to abstract `fetch`/auth so a
WeatherKit adapter can drop in beside Meteosource. Two hard issues called out
explicitly: the **timezone reconciliation discrepancy** and the **IANA timezone-string
gap**. The second is a genuine blocker, not a refactor.

---

## TL;DR

- **Routes and the parse/adapter seam are already provider-agnostic — no change needed there.**
- **`src/weather/fetch.js` and `src/weather/index.js` are hardcoded to Meteosource** (URL, query-string `key` auth, param set, adapter import). This is where the work is.
- WeatherKit's auth is **JWT (ES256, `Authorization: Bearer`)**, not a query-string key — net-new, not yet abstracted.
- **Timezone discrepancy (easier):** WeatherKit returns absolute UTC ISO timestamps, so the `zonedWallTimeToUtcIso` wall-time reconciliation the Meteosource adapter needs becomes a no-op. Good — the seam already tolerates this.
- **Timezone string (blocker):** WeatherKit does **not** return an IANA zone name (`Asia/Dubai`). The entire contract — server-side day/hour bucketing *and* the wire `timezone` field the iOS client renders in — depends on an IANA string. This needs a dedicated resolution step before a WeatherKit adapter can satisfy the contract.

---

## What's already abstracted (leave alone)

### Route layer — fully provider-agnostic ✅
`src/routes/rating.js:15` injects `getWeather` via factory:
```js
createRatingRouter({ getWeather = defaultGetWeather, evaluateAll = defaultEvaluateAll })
```
The route only knows the contract `getWeather(lat, lon) → { forecastStart, timezone, hours }`.
It never names Meteosource. **Nothing here changes for a new provider.**

### Parse/adapter seam — clean ✅
`src/weather/parse.js:8` is already parameterized: `parseWeather(raw, adapter)`.
The adapter (`src/weather/adapters/meteosource.js`) is a pure field-extraction contract:
`extractHours`, `extractMoonPhase`, `timezone`, `forecastStart`, `temp`, `humidity`,
`windSpeed`, `rainFall`, `cloudCover`, `visibility`, `uV`, `dustAlert`.
Writing `adapters/weatherkit.js` implementing the same shape is the straightforward part.
(CLAUDE.md already states: *"Swap this file to change weather provider without touching parse logic."*)

---

## What is NOT abstracted (the actual work)

### 1. `src/weather/fetch.js` — Meteosource-only transport
- `BASE_URL` is a hardcoded Meteosource endpoint (`fetch.js:4`).
- Auth is a query-string `key` param — **no header support, no token concept.**
- WeatherKit needs: a different base URL, `dataSets=forecastHourly` params, and an
  `Authorization: Bearer <jwt>` **header**. `fetch.js` currently has no notion of headers.

### 2. `src/weather/index.js` — Meteosource params + adapter baked in
`getWeather` (`index.js:6-29`) hardcodes the Meteosource param set
(`timezone: 'auto'`, `sections`, `units`, `key: process.env.API_KEY`) and imports
`meteosourceAdapter` directly (`index.js:4`). Neither the fetcher nor the adapter is
selectable here. A provider swap today means editing this file's body, not configuration.

---

## The timezone discrepancy (Meteosource vs WeatherKit)

This is the one place the two providers behave oppositely, and the current code is
shaped around Meteosource's behavior.

**Meteosource (today):** under `timezone=auto` it returns **bare local wall-time** with
no offset/designator (e.g. `"2026-06-10T18:00:00"`). The adapter reconciles this to the
UTC-`Z` `forecastStart` contract via `zonedWallTimeToUtcIso(wallTime, timezone)`
(`adapters/meteosource.js:15-20`, implemented in `timeBoundary.js:71-83`). That helper
does real work: parse-as-UTC → correct by zone offset → second pass for the DST edge.

**WeatherKit:** returns **absolute UTC ISO-8601** timestamps already (`...Z` /
offset-bearing). `zonedWallTimeToUtcIso` already short-circuits on any string ending in
`Z` or `±hh:mm` (`timeBoundary.js:73-75`) — it trusts an absolute instant as-is. So a
WeatherKit adapter's `forecastStart` can pass the raw string straight through (or call
the same helper and get an idempotent no-op). **No new time-math needed for the instant.**

**Takeaway:** the instant/`forecastStart` side is *already* provider-tolerant. This
discrepancy is handled. The next section is the one that isn't.

---

## The IANA timezone-string gap (the real blocker)

Everything downstream of the fetch depends on a **named IANA zone** (`Asia/Dubai`), not
a UTC offset:

- **Server-side bucketing:** `tagLocalDays(hours, forecastStart, timezone)`
  (`timeBoundary.js:85`) feeds `timezone` into `Intl.DateTimeFormat({ timeZone })` to
  compute each hour's `localDay` and `localHour`. `Intl` requires an IANA zone name; a
  numeric offset won't drive it, and an offset can't express DST transitions across the
  7-day horizon.
- **Wire contract:** the response's top-level `timezone` is the IANA string the **iOS
  client renders clock times and day labels in** (CLAUDE.md API contract; ADR-0004). The
  client deliberately renders in the *location's* zone, not the device's — so this field
  must be a real zone name the client's `TimeZone(identifier:)` accepts.

**Meteosource** hands us this for free: it exposes the zone top-level under
`timezone=auto`, and the adapter reads it at `adapters/meteosource.js:8` (`res.timezone`).

**WeatherKit does not return an IANA zone name.** Its payload carries UTC timestamps and
per-record UTC offsets, but no `Asia/Dubai`-style identifier. So a WeatherKit adapter
**cannot** satisfy `adapter.timezone(res)` from the response alone.

**Resolution options (pick one; recommend a dedicated seam):**
1. **`lat`/`lon` → IANA lookup** via a tz-geometry library (e.g. `tz-lookup` /
   `geo-tz`). Offline, no extra network call, returns a true IANA name. **Recommended.**
2. Derive from a separate geocoding/timezone API call — extra latency + failure mode,
   another `UpstreamError` source.
3. Store the zone at location-onboarding time (Issue #5c) and pass it in — but the
   engine contract is `getWeather(lat, lon)` with no zone arg, and the push path (#6c/#6d)
   also needs it server-side, so a server-side lat/lon→zone resolver is cleaner and
   reusable by both paths.

Whichever is chosen, it becomes a **provider-independent step** in `getWeather`, feeding
the resolved `timezone` into both `parseWeather` (so the adapter no longer sources it) and
`tagLocalDays`. For Meteosource, the resolver can still defer to `res.timezone`; for
WeatherKit it uses the lat/lon lookup.

---

## Recommendation — a provider descriptor

Introduce a **provider object** that bundles the three things that vary together
(transport config + param builder + adapter), so `getWeather` selects a provider instead
of hardcoding one. Sketch:

```js
// src/weather/providers/meteosource.js
module.exports = {
  name: 'meteosource',
  buildRequest: ({ lat, lon }) => ({
    url: 'https://www.meteosource.com/api/v1/flexi/point',
    query: { lat, lon, timezone: 'auto', language: 'en', sections: 'all',
             units: 'metric', key: process.env.API_KEY },
    headers: {},
  }),
  adapter: meteosourceAdapter,
  // Meteosource ships the IANA zone in-band; use it.
  resolveTimezone: (res /*, lat, lon */) => res.timezone,
};

// src/weather/providers/weatherkit.js
module.exports = {
  name: 'weatherkit',
  buildRequest: ({ lat, lon }) => ({
    url: `https://weatherkit.apple.com/api/v1/weather/en/${lat}/${lon}`,
    query: { dataSets: 'forecastHourly' },
    headers: { Authorization: `Bearer ${signWeatherKitJWT()}` }, // ES256, cached until exp
  }),
  adapter: weatherKitAdapter,
  // WeatherKit has NO IANA zone in-band — resolve from coordinates.
  resolveTimezone: (_res, lat, lon) => tzFromLatLon(lat, lon),
};
```

Then:

1. **Generalize `fetch.js`** to take `{ url, query, headers }` (or accept a `buildRequest`
   result). It keeps the existing `UpstreamError` wrapping — that contract (network →
   502, non-OK → 502) is provider-independent and should be preserved verbatim so the
   route's `instanceof UpstreamError → 502` mapping still holds.

2. **`getWeather(lat, lon)`** picks the provider (env var, e.g. `WEATHER_PROVIDER`,
   default `meteosource`), calls `fetch` with `buildRequest`, resolves the timezone via
   the provider's `resolveTimezone(res, lat, lon)` **before** parse, then passes the
   resolved zone into `parseWeather` and `tagLocalDays`. Adapter's `timezone` extractor
   either goes away or becomes "provider already resolved it."

3. **New `src/weather/auth/weatherKitJwt.js`** — ES256 JWT signer. Inputs (all new env):
   Apple **Team ID**, **Key ID**, **Service ID** (`sub`), and the **.p8 private key**.
   Token: `iss=teamID`, `sub=serviceID`, `iat`/`exp`, header `kid`+`id`. Cache the token
   in-memory until shortly before `exp` (don't re-sign per request). Missing creds should
   throw the same plain-`Error` guard style as the current `API_KEY` check
   (`index.js:7-9`) → surfaces as 500, distinct from provider 502.

4. **`.env.example`** — add the WeatherKit vars alongside the existing `API_KEY`
   (currently only Meteosource). Document that `API_KEY` is Meteosource-specific and
   rename-worthy (e.g. `METEOSOURCE_API_KEY`) if both providers coexist.

5. **`adapters/weatherkit.js`** — implement the field-extraction contract against
   `forecastHourly.hours[]`. `forecastStart` passes the UTC-`Z` string through (or via the
   idempotent `zonedWallTimeToUtcIso`). Map WeatherKit field names
   (`temperature`, `humidity`, `windSpeed`, `precipitationAmount`, `cloudCover`,
   `visibility`, `uvIndex`) — **watch unit conventions**: WeatherKit humidity/cloudCover
   are 0–1 fractions and visibility is meters; the Meteosource contract is percent + km.
   Normalize in the adapter.

---

## Docs to touch when this is built

- **New ADR** — "pluggable weather provider / provider descriptor" (the adapter-swap
  claim in CLAUDE.md predates a real second provider; formalize the descriptor seam and
  the timezone-resolution decision).
- **`docs/API_documentation/weatherkit/README.md`** — mirror the existing
  `meteosource/README.md`: endpoints, auth (JWT), params, response schema, **unit
  conventions**, refresh cadence, and the "no IANA zone in payload" gotcha.
- **CLAUDE.md** — update the `src/weather/` module map (new `providers/` + `auth/`),
  and correct "sends `timezone: 'auto'`" / "resolved server-side from lat/lon" wording to
  reflect the provider-specific timezone resolution.
- **`.env.example`** — WeatherKit credential block.

---

## Effort estimate

| Piece | Effort | Note |
|---|---|---|
| Route layer | none | already agnostic |
| `adapters/weatherkit.js` | S | field mapping + unit normalization |
| Generalize `fetch.js` (url/query/headers) | S | keep `UpstreamError` wrapping intact |
| Provider descriptor + `getWeather` selection | S–M | env-driven provider pick |
| ES256 JWT signer + creds guard | M | net-new; token caching; new env vars |
| **IANA timezone resolution from lat/lon** | **M** | **blocker — required for correctness, not optional** |
| Docs (ADR, API_documentation, CLAUDE.md, .env) | S | |

**Critical path:** the JWT signer and the lat/lon→IANA resolver are the two genuinely
new capabilities. Everything else is refactoring around seams that already exist.
