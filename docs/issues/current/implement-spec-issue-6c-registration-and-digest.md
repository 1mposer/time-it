# Implementation spec — Issue #6c: Device registration + daily digest push

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — see **Device**, **Device snapshot**, **Digest**, **Active location**.
> Architecture of record: [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) (server-eval, device-keyed; read it first) + [ADR-0001](../../adr/0001-no-accounts-guest-first.md) (anonymous install ID, no accounts).
> Depends on: [#6b](implement-spec-issue-6b-railway-deploy.md) (live deploy) and [#5c](implement-spec-issue-5c-location-onboarding.md) (real-location onboarding — registration requires one).
> Required by: [#6d](implement-spec-issue-6d-perfect-window-detector.md) (reuses every piece of infrastructure built here).
> **Prerequisite (owner, before starting):** Apple Developer account ($99/yr); APNs Auth Key (`.p8`) + Key ID + Team ID from the portal; app registered with bundle ID `com.timeit.app`; a real device (APNs does not work in the Simulator).

This spec is self-contained. Recreated 2026-07-16 from the #6 grill. **TDD required** — the backend suite (114) stays green; new modules get DI-factory tests like `createRatingRouter`.

---

## Context

The backend can now be reached from anywhere (#6b) but holds no device state — and the engine holds no activities ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)). To push, the server needs a device-keyed snapshot to evaluate. This sub-issue builds: Postgres + the `devices` table, the snapshot upsert route, the APNs seam, the weather cache, and the **daily digest** job. The `/rating` path is untouched and stays stateless.

**Decisions made (do not relitigate — all from the 2026-07-16 grill, recorded in [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md)):**
- Full-snapshot upsert, client-authoritative, last-write-wins. No merge, no granular routes, no piggybacking on `/rating`.
- Registration is opt-in (Settings toggle) and requires a real location. Toggle off → `DELETE`.
- Digest: per-device **local 6am**, fixed hour (user-configurable later rides the snapshot with no backend rework); hourly cron pass; `last_digest_date` marker; **one push per device per day**; sent **only** when something qualifies (no "no windows" push).
- Digest content: today/tonight per Activity + **week-ahead Perfect highlights** (buckets 2–6) — the far-out heads-up lives here because #6d's detector is capped at 48h.
- Storage: Railway Postgres, `pg`, idempotent `initDb()` (`CREATE TABLE IF NOT EXISTS`), activities as JSONB. No migration framework.
- Jobs: in-process `node-cron` on the always-on web service; **single replica** (2+ replicas duplicate pushes).
- APNs: `apns2` package behind `src/notifications/`; `.p8` as env-var PEM content (`APNS_KEY`), never a file path.
- Weather cache: in-memory, 30-min TTL, key = lat/lon rounded to 2 dp (~1.1 km — nearby devices share entries). **Jobs only** — the `/rating` route keeps calling `getWeather` directly (freshness semantics unchanged, zero test churn).

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
1. Validate: `deviceId` non-empty string; `apnsToken` non-empty hex string; `home.lat`/`home.lon` in range; `activities` validated with the **same rules as the rating body** — extract the per-activity rule block out of `validateRatingRequest.js` into a shared `validateActivities(activities, pathPrefix = 'activities')`. **Audited 2026-07-16 — extraction is clean with two conditions:** error paths are composed inline as `` `activities[${i}]` ``, so the prefix must be a *parameter*; and the duplicate-`id` check (a `seenIds` set) plus the ~50 ceiling are per-request concerns the shared function must own/receive, not lose. Refactor, not a fork: the rating route's error messages, paths, and tests stay byte-identical. Errors → `400` with the uniform `{ errors: [{ path?, message }] }` envelope (ADR-0005 §6).
   **Second extraction (same reason):** `errorBody()` and the `UpstreamError → 502 / other → 500` mapping are currently **inline in `rating.js`** — pull them into a shared helper (e.g. `src/routes/errorEnvelope.js`) consumed by both routers, so the envelope never forks across three routes. (The malformed-JSON `400`/`413` middleware in `server.js` is already shared — any router mounted there inherits it for free.)
2. Resolve `timezone` by calling the (cached) weather layer for `home` — one call per upsert, also proving the location is servable. Provider failure → `502 { errors }`.
3. Upsert the row (`ON CONFLICT (device_id) DO UPDATE`, refresh `updated_at`; **preserve** `last_digest_date`). → `204`.

**`DELETE /api/v1/devices/:deviceId`** → delete row, `204` (idempotent — deleting a missing row is still `204`).

No auth: the deviceId is an unguessable UUID and the stored data is a weather-preferences snapshot (accepted risk, ADR-0001 threat model).

---

## 5. APNs seam — `src/notifications/apns.js`

Wraps `apns2` (never imported elsewhere — provider-specifics stop at the boundary). Exports `sendPush(apnsToken, { title, body, payload })`. Config from env: `APNS_KEY` (PEM content), `APNS_KEY_ID`, `APNS_TEAM_ID`; topic `com.timeit.app`; production host when `NODE_ENV === 'production'`, sandbox otherwise. **On APNs `410 Unregistered`** (or `BadDeviceToken`): throw a typed `StaleTokenError` so callers delete the device row — dead tokens must not accumulate.

## 6. Weather cache — `src/services/weatherCache.js`

`getCachedWeather(lat, lon)` → in-memory `Map`, key `` `${lat.toFixed(2)},${lon.toFixed(2)}` ``, 30-min TTL, delegates to `getWeather`. Used by jobs only.

---

## 7. Digest job — `src/jobs/dailyDigest.js` + `src/jobs/index.js`

Cron `0 * * * *` (hourly, in-process; started after `listen`). Each pass:

1. Select devices where the **local hour in `timezone` is 6** and (`last_digest_date` is null or < local today). **No new zone math needed (audited 2026-07-16):** `timeBoundary.js` already exports `localHour(instantMs, timezone)` and `localDay(instantMs, timezone)` operating on *arbitrary* instants — `localHour(Date.now(), device.timezone) === 6` and `localDay(Date.now(), device.timezone)` are the selector and the sent-today comparand. Do not hand-roll `Intl` calls in the job.
2. Per device (try/catch per device — one failure never stops the pass): `getCachedWeather(home)` → `evaluateAll(hours, activities)` (hours come back `localDay`/`localHour`-tagged from `getWeather`, exactly what `evaluateAll` needs).
3. Compose **one** push:
   - **Today section:** each Activity whose `days[0].rating` is non-null → "Cycling: Perfect 7–10am" (clock times derived from `forecastStart` + `timezone` + global indices — server-side twin of the iOS `TimeDeriver`; a nocturnal Activity's bucket 0 reads "tonight", per the night-stitch `dayIndex` convention). **Nocturnal detection (audited 2026-07-16): `window` is input-only — `evaluateAll` results echo `activityId`/`label`/`displayMetrics` but NOT `window`** — so keep the snapshot's `activities` array in scope beside the results and read `activities[i].window` (wrapped = nocturnal) when composing copy. **End-bound convention:** `endIndex` is *exclusive* (`[startIndex, endIndex)`, `duration = endIndex − startIndex`) — a `7→10` window is "7–10am", ending as 10am begins.
   - **Week-ahead section:** Activities with a **Perfect** day in buckets 2–6 → "Sat: Perfect for Fishing" (one line per activity, earliest Perfect day).
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

## 9. iOS — opt-in, registration, sync

- **Settings toggle "Notifications"** (the real switch) + a **one-time dismissible dashboard callout** ("Get a morning digest + Perfect-window alerts") that deep-links to it.
- Toggle ON: if no real Active location (picked home or GPS grant), first route the user through the #5c onboarding; then `UNUserNotificationCenter.requestAuthorization` → `registerForRemoteNotifications`.
- **`DeviceRegistration` service:** mints/reads the install UUID from Keychain (survives reinstall, per ADR-0001); on receiving the APNs token (AppDelegate `didRegisterForRemoteNotificationsWithDeviceToken` — hex-encode; the old spec's skeleton minus the JWT header is salvageable), `PUT`s the full snapshot.
- **Re-upsert triggers** (only while the toggle is on): any `ActivityStore` mutation, home-location change, APNs token refresh, and app-launch-if-stale (cheap consistency net). Failures retry on next trigger — no bespoke queue.
- Toggle OFF: `DELETE /api/v1/devices/:deviceId` (keep the Keychain ID).
- Snapshot location = the **home location if set, else the current GPS fix**; never the last-resolved cache and never any fallback constant.

---

## 10. Tests

- `tests/routes/devices.test.js` — DI fakes: upsert happy path (204, row shape, timezone stored), validation 400s (bad token/lat/activities — reusing the shared `validateActivities` cases), `502` on provider failure, DELETE idempotency, `last_digest_date` preserved across upserts.
- `tests/routes/validateRatingRequest.test.js` — unchanged and green after the `validateActivities` extraction (the refactor's tripwire).
- `tests/jobs/dailyDigest.test.js` — fake clock/db/weather/apns: local-6am selection across zones (a Dubai device and a Toronto device fire on different passes), sent-today suppression, per-device error isolation, no-qualifying-windows → no push, copy composition (diurnal + nocturnal "tonight" + week-ahead Perfect line), `StaleTokenError` → row deleted.
- `tests/notifications/apns.test.js` — seam contract with a stubbed transport (config from env, 410 → `StaleTokenError`).
- iOS: `DeviceRegistration` unit tests (Keychain seam, snapshot body, trigger wiring), XCUI for toggle→prompt flow (mock-seamed).

## 11. Acceptance criteria

- [ ] `npm test` green (114 + new suites); iOS suite green.
- [ ] Fresh Railway deploy: `initDb()` creates tables; `/health` still 200 with the DB paused (liveness independent of Postgres).
- [ ] Real device: toggle on → permission prompt → row appears in `devices` with resolved IANA timezone.
- [ ] Editing an Activity re-upserts the snapshot (row's `activities` JSONB changes).
- [ ] Manually invoking the digest job for a device whose local hour is forced to 6 delivers **one** push listing today's windows (+ week-ahead Perfect line when present); a second invocation the same local day sends nothing.
- [ ] Toggle off deletes the row; a stale-token send deletes the row.
- [ ] `/rating` behaviour and tests are byte-identical (still stateless, still uncached).

---

## Related artifacts

- [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) — the architecture + rejected alternatives.
- [#6d](implement-spec-issue-6d-perfect-window-detector.md) — adds the detector on this infrastructure.
- [ADR-0005](../../adr/0005-custom-activity-request-schema.md) — the activity schema the snapshot reuses.
