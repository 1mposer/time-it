# Meteosource — API reference (standard tier)

Trimmed for agent lookup — read this first. Full raw export: [`openapi.json`](openapi.json) in this dir (the interactive OpenAPI/Swagger doc pulled from the Meteosource dashboard for the **Standard plan**, saved 2026-08-11; it replaced the Flexi-plan export of 2026-07-20 when the subscription was upgraded — git history keeps the old one). Drop to it only when this summary doesn't answer the question.

## What we call

- Endpoint: `GET https://www.meteosource.com/api/v1/standard/point` (`src/weather/fetch.js`)
- **The path segment is subscription-scoped**: the key only works on its own plan's path — calling another tier's path returns `403 {"detail":"The API key is not allowed to use this tier"}` (live-verified 2026-08-11 against the old `/flexi/point`). A future plan change therefore requires a matching `BASE_URL` edit in `fetch.js`, or every live path 502s.
- Params sent (`src/weather/index.js`): `lat`, `lon`, `timezone=auto` (the only mode that exposes the location's IANA zone — but it returns *local* wall-time timestamps, reconciled to UTC-`Z` in the adapter), `language=en`, `sections=all`, `units=metric`, `key` (our `API_KEY` env var; the vendor also accepts an `X-API-Key` header — unused here, we send it as a query param)

## Sections (`sections=all` requests every one; only `hourly` is consumed)

`current`, `daily`, `daily-parts` (morning/afternoon/evening — **first 7 days of the forecast only**, a vendor limitation), `hourly`, `minutely` (1-minute precipitation resolution), `alerts`. `parse.js` reads `hourly` exclusively — the rest of the `all` payload is fetched over the wire but discarded today. Live cost lever if payload size or provider billing-by-response-size ever matters: drop to `sections=hourly`; confirm nothing downstream implicitly depends on another section first.

## Known field behavior (from live testing + the schema — not assumption)

- The `standard` tier returns ~161–168 hourly entries — the 7×24 ceiling `parse.js` slices to (ADR-0003). Live-verified 2026-08-11: 166 hourly entries for Dubai, `timezone: Asia/Dubai`. `/free/` caps at 24h and is unusable for our 7-day horizon.
- `uv_index` is `null` at night upstream — the adapter defaults it to `0` (a true reading, not a placeholder; this is what fixed the live decode bug found 2026-07-12).
- `wind.speed`, `precipitation.total`, `cloud_cover.total` can each be individually absent/null per hour — the adapter maps these to `null`; `checkThreshold` fails a threshold on `null`/`undefined` rather than coercing.

## What the export does NOT document

The OpenAPI export describes request/response *shape* only, and it is near-identical across plans (the Standard export differs from the old Flexi one solely in the server URL, the title, and richer cloud-layer field descriptions — deep-diffed 2026-08-11). Per-plan entitlements — hourly-horizon length, request quota, historical depth, minutely/alerts availability — are **not** stated per-plan anywhere in it (the `/point` description says "depending on the tier" generically). The [Meteosource dashboard](https://www.meteosource.com/client) / pricing page is the source for those; record any load-bearing entitlement here as an owner-confirmed fact when it matters.

- **Refresh cadence / rate limits — owner-confirmed (2026-07-20):** upstream refresh cadence is somewhere between every 10 minutes and every 1 hour. Chosen policy: cache/poll at the **hourly** end of that range — do not build a cache TTL or cron cadence tighter than 60 minutes chasing the fast end of that window; at this traffic scale the cost isn't worth it. This is the stated basis for the 60-min `getCachedWeather` TTL ([#6c spec](../../issues/completed/implement-spec-issue-6c-registration-and-digest.md) §6).

## Other endpoints in this plan (present in `openapi.json`, unused today)

`/find_places`, `/find_places_prefix`, `/nearest_place`, `/map`, `/time_machine` (historical), `/air_quality` — none currently called. `/air_quality` is the likely landing spot for a future AQ metric (grill Q4).
