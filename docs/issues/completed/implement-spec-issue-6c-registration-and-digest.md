# Implementation spec — Issue #6c: Device registration + daily digest push

> ✅ **Backend BUILT + MERGED 2026-08-01, DEPLOYED 2026-08-03 — historical record; do not build from this.** As-built truth: `CLAUDE.md` (push-path section). The remaining work — the §9 iOS opt-in client and the unticked live-acceptance boxes in §11 — is **extracted** to [`../current/implement-spec-push-client.md`](../current/implement-spec-push-client.md).

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — see **Device**, **Device snapshot**, **Digest**, **Active location**.
> Architecture of record: [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) (server-eval, device-keyed; read it first) + [ADR-0001](../../adr/0001-no-accounts-guest-first.md) (anonymous install ID, no accounts).
> Depends on: [#6b](implement-spec-issue-6b-railway-deploy.md) (live deploy) and [#5c](implement-spec-issue-5c-location-onboarding.md) (real-location onboarding — ✅ built 2026-08-01; registration requires one).
> Required by: [#6d](implement-spec-issue-6d-perfect-window-detector.md) (reuses every piece of infrastructure built here).
> **Prerequisite (owner, before starting):** Apple Developer account ($99/yr); APNs Auth Key (`.p8`) + Key ID + Team ID from the portal; app registered with bundle ID `com.timeit.app.dev` (the un-suffixed `com.timeit.app` belongs to another Apple account — owner decision 2026-08-03); a real device (APNs does not work in the Simulator).

This spec is self-contained. Recreated 2026-07-16 from the #6 grill. **TDD required** — the backend suite (114) stays green; new modules get DI-factory tests like `createRatingRouter`.

---

## Context

The backend can now be reached from anywhere (#6b) but holds no device state — and the engine holds no activities ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)). To push, the server needs a device-keyed snapshot to evaluate. This sub-issue builds: Postgres + the `devices` table, the snapshot upsert route, the APNs seam, the weather cache, and the **daily digest** job. The `/rating` path stays stateless — no per-device state — but **amended 2026-07-20**: it now shares the same weather cache as the jobs (§6) instead of calling the provider fresh on every request; see the Decisions-made bullet below and §6 for the reasoning and required change.

**Decisions made (do not relitigate — all from the 2026-07-16 grill, recorded in [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md)):**
- Full-snapshot upsert, client-authoritative, last-write-wins. No merge, no granular routes, no piggybacking on `/rating`.
- Registration is opt-in (Settings toggle) and requires a real location. Toggle off → `DELETE`.
- Digest: per-device **local 6am**, fixed hour (user-configurable later rides the snapshot with no backend rework); hourly cron pass; `last_digest_date` marker; **one push per device per day**; sent **only** when something qualifies (no "no windows" push).
- Digest content: today/tonight per Activity + **week-ahead Perfect highlights** (buckets 2 through each activity's `days.length − 1` — see §7) — the far-out heads-up lives here because #6d's detector is capped at 48h.
- Storage: Railway Postgres, `pg`, idempotent `initDb()` (`CREATE TABLE IF NOT EXISTS`), activities as JSONB. No migration framework.
- Jobs: in-process `node-cron` on the always-on web service; **single replica** (2+ replicas duplicate pushes).
- APNs: `apns2` package behind `src/notifications/`; `.p8` as env-var PEM content (`APNS_KEY`), never a file path.
- Weather cache: in-memory, **60-min TTL** (amended 2026-07-20 from an earlier 30-min figure — owner-confirmed Meteosource's `flexi` tier refreshes upstream somewhere between every 10 min and every 1 hour, not documented in the vendor's OpenAPI export; see [`docs/API_documentation/meteosource/README.md`](../../API_documentation/meteosource/README.md). Policy is to cache at the hourly end of that range, not chase the 10–15 min end — the cost isn't worth it at this traffic scale), key = lat/lon rounded to 2 dp (~1.1 km — nearby devices share entries). **Used by the jobs, the device upsert's timezone resolution, AND `/rating`** (amended 2026-07-20 — reverses the original job-only scoping: live dashboard traffic, not just the hourly cron passes, is the largest source of duplicate provider calls, since every app foreground/pull-to-refresh re-fetches identical data for the same location). Same file, same TTL semantics for every caller — do not build a second cache implementation for `/rating`. See §6 for the resulting required change to `createRatingRouter`'s default wiring.

---

## 1. Manual Railway steps

1. Project → **+ New → Database → PostgreSQL** (Railway injects `DATABASE_URL`).
2. Variables: add `APNS_KEY` (paste the full `.p8` PEM content), `APNS_KEY_ID`, `APNS_TEAM_ID`.
3. Confirm single replica + app sleeping still off.

---

## 2. Dependencies

```
npm install pg node-cron apns2
```

---

## 3. Schema — `src/db.js`

Exports `query` (pool passthrough) and `initDb()` (idempotent):

```sql
CREATE TABLE IF NOT EXISTS devices (
  device_id        TEXT PRIMARY KEY,          -- client-minted Keychain install UUID (ADR-0001)
  apns_token       TEXT NOT NULL,
  home_lat         DOUBLE PRECISION NOT NULL,
  home_lon         DOUBLE PRECISION NOT NULL,
  timezone         TEXT NOT NULL,             -- IANA zone resolved server-side at upsert
  activities       JSONB NOT NULL,            -- the validated ADR-0005 activities[] snapshot
  last_digest_date DATE,                      -- local-date marker: digest sent for this local day
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`app.js` becomes: `initDb().then(() => app.listen(...listen callback starts jobs...))`, exiting non-zero on init failure. `GET /health` must **not** depend on the DB (Railway liveness).

---

## 4. Routes — `src/routes/devices.js`

`createDevicesRouter({ getWeather, db })` factory (DI, same pattern as `createRatingRouter`).

**`PUT /api/v1/devices/:deviceId`** — body `{ apnsToken, home: { lat, lon }, activities: [...] }`:
1. Validate: `deviceId` non-empty string; `apnsToken` non-empty hex string; `home.lat`/`home.lon` in range; `activities` validated with the **same rules as the rating body** — extract the per-activity rule block out of `validateRatingRequest.js` into a shared `validateActivities(activities, pathPrefix = 'activities')`. **Audited 2026-07-16 — extraction is clean with two conditions:** error paths are composed inline as `` `activities[${i}]` ``, so the prefix must be a *parameter*; and the duplicate-`id` check (a `seenIds` set) plus the ~50 ceiling are per-request concerns the shared function must own/receive, not lose. **One deliberate divergence (audit 2026-07-16): an empty `activities: []` is VALID here.** The rating route rejects empty (rating nothing is meaningless), but the client re-upserts on *any* `ActivityStore` mutation (§9) — deleting the last Activity sends `[]`; under rating rules that 400s, the stale snapshot survives, and the device keeps receiving pushes for deleted Activities until opt-out. An empty snapshot is a valid *dormant* registration: `evaluateAll(hours, [])` returns `[]`, so both jobs naturally compose nothing and send nothing. (The non-empty rule is therefore a per-caller concern beside the ceiling, owned by the rating route.) Refactor, not a fork: the rating route's error messages, paths, and tests stay byte-identical. Errors → `400` with the uniform `{ errors: [{ path?, message }] }` envelope (ADR-0005 §6).
   **Second extraction (same reason):** `errorBody()` and the `UpstreamError → 502 / other → 500` mapping are currently **inline in `rating.js`** — pull them into a shared helper (e.g. `src/routes/errorEnvelope.js`) consumed by both routers, so the envelope never forks across three routes. (The malformed-JSON `400`/`413` middleware in `server.js` is already shared — any router mounted there inherits it for free.)
2. Resolve `timezone` by calling the (cached) weather layer for `home` — one call per upsert, also proving the location is servable. Provider failure → `502 { errors }`.
3. Upsert the row (`ON CONFLICT (device_id) DO UPDATE`, refresh `updated_at`; **preserve** `last_digest_date`). → `204`.

**`DELETE /api/v1/devices/:deviceId`** → delete row, `204` (idempotent — deleting a missing row is still `204`).

No auth: the deviceId is an unguessable UUID and the stored data is a weather-preferences snapshot (accepted risk, ADR-0001 threat model).

---

## 5. APNs seam — `src/notifications/apns.js`

Wraps `apns2` (never imported elsewhere — provider-specifics stop at the boundary). Exports `sendPush(apnsToken, { title, body, payload })`. Config from env: `APNS_KEY` (PEM content), `APNS_KEY_ID`, `APNS_TEAM_ID`; topic from optional `APNS_TOPIC`, defaulting to `com.timeit.app.dev` (must equal the installed app's bundle ID — `1f22706`); production host when `NODE_ENV === 'production'`, sandbox otherwise. **On APNs `410 Unregistered`** (or `BadDeviceToken`): throw a typed `StaleTokenError` so callers delete the device row — dead tokens must not accumulate.

## 6. Weather cache — `src/services/weatherCache.js`

`getCachedWeather(lat, lon)` → in-memory `Map`, key `` `${lat.toFixed(2)},${lon.toFixed(2)}` ``, **60-min TTL** (see Decisions made, and [`docs/API_documentation/meteosource/README.md`](../../API_documentation/meteosource/README.md) for the upstream-cadence rationale), delegates to `getWeather`. Used by the jobs, the upsert's timezone resolution (§4.2), and — **amended 2026-07-20, reversing the original scoping** — `src/routes/rating.js` as well: `createRatingRouter`'s default `getWeather` dependency should resolve to `getCachedWeather` rather than the raw `getWeather`, so live `/rating` traffic shares the same cache as the push jobs instead of issuing a fresh provider call on every request. The router's injected-dependency signature (the same DI pattern `tests/server/rating.test.js` already relies on) does not need to change — only the production wiring in `app.js`/`src/server.js` swaps which function is passed in. The wire response contract is byte-identical; only the fetch is memoized. New test coverage needed: a second `/rating` request for an already-cached location within the TTL must not call the provider twice (existing DI-fake tests currently assume one call per request and will need a cache-aware fake or a shared-cache fixture to catch a regression here).

---

## 7. Digest job — `src/jobs/dailyDigest.js` + `src/jobs/index.js`

Cron `0 * * * *` (hourly, in-process; started after `listen`). Each pass:

1. Select devices where the **local hour in `timezone` is in `6..11`** and (`last_digest_date` is null or < local today). **`6 ≤ h < 12`, not `=== 6` (audit 2026-07-16):** the strict-6 selector gives exactly one eligible tick per day, so an in-process cron restart across that tick (Railway redeploys on every push to `main`, #6b) silently drops the digest for a whole timezone band for the day; the `last_digest_date` marker already makes catch-up idempotent, so a late pass delivers once and only once (the normal case still fires at 6am sharp; past noon, skip — a "morning" digest at 9pm is worse than none). **No new zone math needed (audited 2026-07-16):** `timeBoundary.js` already exports `localHour(instantMs, timezone)` and `localDay(instantMs, timezone)` operating on *arbitrary* instants — those are the selector and the sent-today comparand. Do not hand-roll `Intl` calls in the job. **Type trap (audit 2026-07-16):** `localDay` returns a `'YYYY-MM-DD'` string but `pg` returns `DATE` columns as JS `Date` objects, and `dateObject < 'YYYY-MM-DD'` is **always false** in JS (the string coerces to NaN) — a JS-side comparison silently means *one digest per device, ever*. Compare in SQL (`last_digest_date IS NULL OR last_digest_date < $1::date`, string param) or store the marker as `TEXT`; either way the test fake must reproduce the real driver's `Date`-object shape (a string-returning fake would mask the bug).
2. Per device (try/catch per device — one failure never stops the pass): `getCachedWeather(home)` → `evaluateAll(hours, activities)` (hours come back `localDay`/`localHour`-tagged from `getWeather`, exactly what `evaluateAll` needs).
3. Compose **one** push:
   - **Today section:** each Activity whose `days[0].rating` is non-null → "Cycling: Perfect 7–10am" (clock times derived from `forecastStart` + `timezone` + global indices — server-side twin of the iOS `TimeDeriver`; known shared limitation: half-hour zones (e.g. Asia/Kolkata +05:30) render `ha`-style labels :30 off — cosmetic, tracked in STATUS §5; a nocturnal Activity's bucket 0 reads "tonight", per the night-stitch `dayIndex` convention). **Nocturnal detection (audited 2026-07-16): `window` is input-only — `evaluateAll` results echo `activityId`/`label`/`displayMetrics` but NOT `window`** — so keep the snapshot's `activities` array in scope beside the results and read `activities[i].window` (wrapped = nocturnal) when composing copy. **End-bound convention:** `endIndex` is *exclusive* (`[startIndex, endIndex)`, `duration = endIndex − startIndex`) — a `7→10` window is "7–10am", ending as 10am begins.
   - **Week-ahead section:** Activities with a **Perfect** day in buckets **2 through `days.length − 1`** → "Sat: Perfect for Fishing" (one line per activity, earliest Perfect day; the weekday label = date-of-day-0 + `dayIndex`, the same helper as #6d's `bucket_date`). **Never write `2–6` in code** (audit 2026-07-16): `days.length` is per-activity — a diurnal horizon is *usually 8* buckets (a hardcoded 2–6 would permanently hide a Perfect on the partial tail day from every push, since the detector stops at bucket 1), and a nocturnal activity can have 6 (a literal `days[6]` read is out of bounds). **Bucket 1 is deliberately absent from the digest** (the today-section reads `days[0]` only): tomorrow's Perfect belongs to the #6d detector; tomorrow's *Good* surfaces in-app only — an ADR-0006 trade-off, not an oversight.
   - Both sections empty → **no push.**
4. Send via the seam; on `StaleTokenError` delete the device row; on success set `last_digest_date` = device-local today.

---

## 8. `.env.example` additions

```
DATABASE_URL=postgres://localhost:5432/timeit
APNS_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
```

---

## 9. iOS — opt-in, registration, sync *(EXTRACTED 2026-08-10 → [`../current/implement-spec-push-client.md`](../current/implement-spec-push-client.md); the text below is the original record)*

- **Settings toggle "Notifications"** (the real switch) + a **one-time dismissible dashboard callout** ("Get a morning digest + Perfect-window alerts") that deep-links to it.
- Toggle ON: if no real Active location (picked home or GPS grant), first route the user through the #5c onboarding; then `UNUserNotificationCenter.requestAuthorization` → `registerForRemoteNotifications`.
- **`DeviceRegistration` service:** mints/reads the install UUID from Keychain (survives reinstall, per ADR-0001); on receiving the APNs token (AppDelegate `didRegisterForRemoteNotificationsWithDeviceToken` — hex-encode; the deleted #6 spec's skeleton minus the JWT header is salvageable — retrieve it from git history), `PUT`s the full snapshot.
- **Re-upsert triggers** (only while the toggle is on): any `ActivityStore` mutation, home-location change, APNs token refresh, and app-launch-if-stale (cheap consistency net). Deleting the *last* Activity upserts an **empty** snapshot — valid per §4, keeping the registration dormant rather than stale. Failures retry on next trigger — no bespoke queue.
- Toggle OFF: `DELETE /api/v1/devices/:deviceId` (keep the Keychain ID).
- Snapshot location = the **home location if set, else the current GPS fix**; never the last-resolved cache and never any fallback constant.

---

## 10. Tests

- `tests/routes/devices.test.js` — DI fakes: upsert happy path (204, row shape, timezone stored), **empty-`activities` upsert → 204 (dormant snapshot, §4)**, validation 400s (bad token/lat/activities — reusing the shared `validateActivities` cases), `502` on provider failure, DELETE idempotency, `last_digest_date` preserved across upserts.
- `tests/routes/validateRatingRequest.test.js` — unchanged and green after the `validateActivities` extraction (the refactor's tripwire).
- `tests/jobs/dailyDigest.test.js` — fake clock/db/weather/apns: local-6am selection across zones (a Dubai device and a Toronto device fire on different passes), **catch-up path** (a device whose 6am tick was missed is picked up at 7–11 local, once; past noon → skipped), sent-today suppression **with the fake db returning a real `Date` object for `last_digest_date`** (the pg driver shape — a string-returning fake masks the §7 type trap), per-device error isolation, no-qualifying-windows → no push, copy composition (diurnal + nocturnal "tonight" + week-ahead Perfect line, incl. an 8-bucket horizon whose tail-day Perfect appears and a 6-bucket nocturnal that doesn't over-index), `StaleTokenError` → row deleted.
- `tests/notifications/apns.test.js` — seam contract with a stubbed transport (config from env, 410 → `StaleTokenError`).
- iOS: `DeviceRegistration` unit tests (Keychain seam, snapshot body, trigger wiring), XCUI for toggle→prompt flow (mock-seamed).

## 11. Acceptance criteria

> Backend boxes ticked 2026-08-10 (built, merged, deployed); the unticked device/live boxes are extracted to the [push-client spec](../current/implement-spec-push-client.md) §6.

- [x] `npm test` green (backend suite now 172); iOS suite green (138).
- [x] Fresh Railway deploy: `initDb()` created both tables in production 2026-08-03; `/health` 200.
- [ ] Real device: toggle on → permission prompt → row appears in `devices` with resolved IANA timezone.
- [ ] Editing an Activity re-upserts the snapshot (row's `activities` JSONB changes).
- [ ] Manually invoking the digest job for a device whose local hour is forced to 6 delivers **one** push listing today's windows (+ week-ahead Perfect line when present); a second invocation the same local day sends nothing.
- [ ] Toggle off deletes the row; a stale-token send deletes the row.
- [x] `/rating` response contract is byte-identical (still stateless — no per-device state) — but per the §6 amendment (2026-07-20) it now reads through the shared `getCachedWeather`, not a direct `getWeather` call: a repeat request for an already-cached location within the 60-min TTL must not hit the provider twice (pinned by `tests/server/ratingCache.test.js`).

---

## Related artifacts

- [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) — the architecture + rejected alternatives.
- [#6d](implement-spec-issue-6d-perfect-window-detector.md) — adds the detector on this infrastructure.
- [ADR-0005](../../adr/0005-custom-activity-request-schema.md) — the activity schema the snapshot reuses.
