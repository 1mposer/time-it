# Implementation spec — Issue #6d: Perfect-window detector

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — see **Perfect-window alert**, **Device snapshot**.
> Architecture of record: [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md).
> Depends on: [#6c](implement-spec-issue-6c-registration-and-digest.md) — reuses the `devices` table, weather cache, APNs seam, cron bootstrap, and per-device error isolation verbatim.

This spec is self-contained. Recreated 2026-07-16 from the #6 grill. **TDD required.**

---

## Context

The digest (#6c) is a scheduled summary; the detector is the event: **push the moment a new Perfect window appears** in a device's near-term forecast. The pre-rebuild design deduped on `startIndex` — broken, because global indices re-base against every fresh `forecastStart` (the same window would re-alert hourly). Dedup is re-founded on the **bucket**, the engine's own stable unit.

**Decisions made (do not relitigate — grill 2026-07-16, [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md)):**
- **Perfect-only.** Good windows never trigger the detector — they belong to the digest. A good→perfect upgrade alerts **inherently**: it is that bucket's first Perfect (this satisfies the upgrade requirement with no rating column).
- **At most one alert per (device, activity, bucket).** Key = `(device_id, activity_id, bucket_date)` where `bucket_date` is the bucket's local calendar date (for a nocturnal Activity: the **evening's** date, matching the night-stitch `dayIndex` convention). Forecast jitter that shifts a window's start ±1h cannot re-alert.
- **Horizon: buckets 0–1 only** (today/tonight + tomorrow, ~48h). Far-out Perfect days are volatile and there is no retraction push; they reach the user via the digest's week-ahead section instead. Also caps the first-registration burst at 2 alerts per activity.
- **Skip already-ended windows** (window `endIndex` hour entirely in the past); an **ongoing** window still alerts ("Perfect now until 6pm").
- **Accepted blind spot (audit 2026-07-16):** the night-stitch drops the pre-horizon **orphan morning** (`bucketNightWindow`, ADR-0003), so after local midnight the *in-progress* night is invisible to evaluation — a good→perfect upgrade materialising after midnight (e.g. at 00:30 for a `22→4` window) never alerts for the remainder of that night, and bucket 0 / "Tonight" then means the *next* evening. Accepted as-is: the alternative is a second cross-midnight exception inside the engine; the miss is bounded by the window's `endHour` hours and the night was already visible (and alertable) every pass before midnight.

---

## 1. Schema addition (extend `initDb()`)

```sql
CREATE TABLE IF NOT EXISTS notification_state (
  device_id   TEXT NOT NULL REFERENCES devices(device_id) ON DELETE CASCADE,
  activity_id TEXT NOT NULL,
  bucket_date DATE NOT NULL,
  notified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, activity_id, bucket_date)
);
```

Each pass ends by pruning rows with `bucket_date < (today - 2 days)` — the table stays O(devices × activities × 2).

## 2. Job — `src/jobs/perfectWindowDetector.js`

Cron `0 * * * *` (registered in `src/jobs/index.js` beside the digest). Each pass, per device (try/catch isolation as in #6c):

1. `getCachedWeather(home)` → `evaluateAll(hours, activities)` — the 60-min cache (amended 2026-07-20 from an earlier 30-min figure — see #6c §6 and [`docs/API_documentation/meteosource/README.md`](../../API_documentation/meteosource/README.md) for the upstream-cadence basis) means digest and detector passes in the same hour share one provider call per location — and, since #6c's amendment, so does any live `/rating` traffic for that same location in the same window.
2. For each activity, for `days[i]` with `i ∈ {0, 1}` and `rating === 'perfect'` and window not already ended. **Index semantics (audited 2026-07-16, pinned by `decision_engine.js` + its tests): `endIndex` is EXCLUSIVE** — a window is `[startIndex, endIndex)`, `duration = endIndex − startIndex`, a single-hour window is `start 5, end 6`. So: **"already ended"** = `forecastStart + endIndex hours ≤ now`; **"ongoing"** = start instant passed but end instant not. An off-by-one here goes straight into push copy — treat this as contract, not detail. Then:
   - `bucket_date` = the bucket's calendar date: `localDay(forecastStart, timezone)` advanced by `dayIndex` **calendar days** (one helper beside `timeBoundary.js`, unit-tested; pure date addition, DST-safe; do not hand-roll zone math outside `timeBoundary.js`). **Do NOT derive it from `hours[startIndex]`** (audit 2026-07-16): a nocturnal bucket spans midnight, so a Perfect window starting in the **morning tail** has `hours[startIndex].localDay` = the *morning's* date (evening + 1) — breaking the dedup convention above both ways: jitter that shifts a night's window across midnight between runs re-alerts the same night, and the misfiled key suppresses the real next-night alert. `dayIndex` is the evening's ordinal by construction (`bucketNightWindow` indexes by evening), so date-of-day-0 + `dayIndex` is correct for diurnal and nocturnal alike — the same derivation the iOS `TimeDeriver.dayName` already uses.
   - `INSERT ... ON CONFLICT DO NOTHING`; **only if the row was actually inserted**, send the push (insert-first makes a crash after insert fail *silent*, never *duplicate* — preferring a missed alert over spam).
3. Copy: "Perfect Cycling window" / "Today 7–10am (3h)" — times in the device's stored `timezone`; the end clock label derives from the **exclusive** bound (a `7→10` window is "7–10am"); nocturnal bucket 0 reads "Tonight" — determined from the **snapshot's** `activities[i].window` (wrapped = nocturnal), because `window` is input-only and is **not** echoed in `evaluateAll` results (audited 2026-07-16); ongoing windows read "now until 6pm". Payload carries `{ activityId, bucketDate }`.
4. `StaleTokenError` → delete the device row (cascade clears its state rows).

## 3. Tests — `tests/jobs/perfectWindowDetector.test.js`

Fake clock/db/weather/apns:
- New Perfect in bucket 0 → one push + one state row; re-run same forecast → nothing (the old `startIndex` bug's regression test: re-run with a **re-based** `forecastStart` one hour later, same real-world window → still nothing).
- Good-only bucket → nothing; upgrade to Perfect on a later run → push (the inherent-upgrade path).
- Perfect in bucket 2 → nothing (horizon cap). Ended window → nothing; ongoing window → push with "now until" copy.
- Nocturnal activity: bucket-0 Perfect keys on the **evening's** date and reads "Tonight".
- **Morning-tail nocturnal (the audit's trap — an evening-start fixture cannot catch it):** a Perfect window entirely after midnight (window `22→4`, Perfect 01:00–03:00) still keys on the **evening's** date; forecast jitter shifting a night's window across midnight between runs (23:00–01:00 → 00:30–02:30) does **not** re-alert and does **not** consume the next night's key.
- Two activities, one device: independent state rows. Pruning removes old rows. Insert-conflict race → no duplicate push.

## 4. Acceptance criteria

- [ ] Full backend suite green (#6c suites untouched).
- [ ] Live: force a Perfect window (loose thresholds) → exactly one push; the next hourly run re-sends nothing.
- [ ] Tighten thresholds so the bucket is Good-only, then loosen → the upgrade push arrives.
- [ ] A Perfect day 3+ days out never triggers the detector but shows in the next digest's week-ahead line.
- [ ] `notification_state` stays pruned (no unbounded growth).

---

## Related artifacts

- [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) — dedup + horizon rationale.
- [#6c](implement-spec-issue-6c-registration-and-digest.md) — the infrastructure this reuses.
- [ADR-0003](../../adr/0003-seven-day-horizon-flat-hours-day-buckets.md)/[ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md) — bucket + night-stitch semantics the dedup key leans on.
