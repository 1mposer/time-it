# Handoff — #6d detector built, ready for audit

**To:** the auditing agent / owner
**Date:** 2026-08-01 (late evening)
**From:** implementing agent (same session that pushed the audited #6c backend to `main`)
**Branch:** `issue-6d-perfect-window-detector` (3 implementation commits + this docs commit; branched from `main` at `ae8968f` — the merged #6c tip)

Scope delivered: the **backend** of [#6d](implement-spec-issue-6d-perfect-window-detector.md) — schema, detector job, tests, cron wiring, docs. The iOS opt-in client (#6c §9) remains unbuilt and is untouched by this work.

## What was built (commit order)

1. **Labels extraction (refactor, not fork)** — `src/jobs/labels.js` (`hourLabel`/`rangeLabel`) pulled out of `dailyDigest.js` so the detector shares the exact clock-label copy. The 14 digest tests passed unchanged immediately after (the tripwire).
2. **Schema** — `initDb()` grew the spec §1 `notification_state` table **verbatim**: PK `(device_id, activity_id, bucket_date)`, `REFERENCES devices ON DELETE CASCADE`, `notified_at` default `now()`. Still idempotent `CREATE TABLE IF NOT EXISTS` — a fresh deploy or a redeploy over the existing #6c database both converge.
3. **Detector job** — `src/jobs/perfectWindowDetector.js`, `createPerfectWindowDetectorJob({ db, getWeather, evaluateAll, sendPush, now })` (the #6c DI shape). Per device (try/catch isolation): shared-cache weather → `evaluateAll` → for `days[0..1]` with `rating === 'perfect'`:
   - **ended-window skip first** (`forecastStart + endIndex·1h ≤ now` — `endIndex` exclusive, per the pinned engine contract), *before* the insert, so an ended window consumes no dedup key;
   - `bucket_date` = `timeBoundary.bucketDate(forecastStart, timezone, dayIndex)` — **never** derived from indices or `hours[startIndex].localDay` (the spec's two audited traps);
   - `INSERT … ON CONFLICT DO NOTHING`; push **only** when `rowCount === 1` (insert-first: a crash between insert and send is a silent miss, never spam);
   - copy: title `Perfect {label} window`; body `Today 7–10am (3h)` / `Tomorrow …` (nocturnal from the *snapshot's* `window`: `Tonight …` / `Tomorrow night …`); ongoing → `Now until 10am`; payload `{ type: 'perfectWindow', activityId, bucketDate }`;
   - `StaleTokenError` → `DELETE FROM devices` (state rows cascade), remaining alerts for that device skipped;
   - end of pass: `DELETE FROM notification_state WHERE bucket_date < $1::date - 2`.
   Wired in `src/jobs/index.js` on the **same** hourly tick as the digest, sequentially, each pass with its own catch — sharing the 60-min cache keeps it at one provider call per location per hour across both jobs.

## Claims — exactly what I ran

- `npm test`: **171 pass, 0 fail** (154 pre-existing + 17 new detector tests). Also green under `TZ=America/New_York`, `TZ=Asia/Kolkata`, and `TZ=UTC`.
- The spec §3 matrix is covered, including: the **re-based `forecastStart` regression** (the old `startIndex`-dedup bug — same real-world window one hour later, shifted indices, no re-alert), the **morning-tail nocturnal trap** (window `22→4`, Perfect entirely after midnight keys on the *evening's* date; cross-midnight jitter neither re-alerts nor consumes the next night's key — proven by a third pass where the next night still alerts), good→perfect upgrade, bucket-2 horizon cap, exact-boundary ended check, insert-conflict race, pruning with strict `<`, stale-token cascade, per-device isolation, dormant `[]` snapshot.
- The test db fake is **stateful across passes** (the state set persists), so re-run tests exercise real dedup semantics rather than canned rowCounts.

## NOT verified (no way to, from this machine)

- `initDb()` against a real Postgres (same gap as #6c — the SQL is the spec block verbatim, but "redeploy adds the table" is unproven until the next Railway deploy; the add-on now exists per the owner).
- Any real APNs send, and the four live acceptance criteria in spec §4 (force-Perfect → exactly one push; Good→Perfect upgrade push; day-3 Perfect reaching only the digest; live prune behavior). These need the owner's APNs credentials + a real device.

## Judgement calls within the spec's latitude (flag if you disagree)

- **Payload** — spec says "Payload carries `{ activityId, bucketDate }`"; I added `type: 'perfectWindow'` alongside, mirroring the digest's `{ type: 'dailyDigest' }` so the iOS client can route on one discriminator field.
- **Bucket-1 nocturnal label** — unspecified; reads `Tomorrow night` (diurnal bucket 1 reads `Tomorrow`).
- **Ongoing copy** — `Now until 10am` (no day label): the spec's own example is "Perfect now until 6pm", and "now" makes a day word redundant.
- **Prune "today"** — computed as **UTC** today from the injected clock. Per-device local dates would be more literal, but the 2-day slack dwarfs any zone offset (no live key can be < today − 2 in any zone) and it keeps the prune a single query.
- **StaleTokenError stops the device's remaining alerts** in the same pass (the token is dead; further sends can only fail) — the already-inserted key for the failed send cascades away with the row, so a re-registered device can be alerted again.
- **Both jobs on one tick, digest first** — the spec says "registered beside the digest" with the same cron expression; running them sequentially in one callback (each with its own catch) avoids two interleaved db/cache storms while keeping failure independence.

## Owner manual steps (unchanged from #6c; Postgres add-on reported DONE)

APNs Auth Key `.p8` + Key ID + Team ID as Railway vars (`APNS_KEY` = PEM **content**), app `com.timeit.app`, single replica confirmed, real device for the live acceptance pass.

## Next after this

- iOS §9/§10 push opt-in + registration client (blocked on the APNs entitlement and the WeatherKit-track pbxproj — constraint unchanged).
- #7 marine data / #8 `requireTrue` remain parallel.
