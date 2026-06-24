# STATUS — project orientation hub

> **Last updated: 2026-06-24** — **Phase 2 implemented on `rebuild/phase-2-custom-activities` (code + code-docs, pre-merge).** Request flip shipped: `POST /api/v1/rating` with body `{ lat, lon, activities[] }`, caller-supplied `evaluateAll(hours, activities)` (engine holds no list; `src/activities/*` deleted), atomic structured `{ errors[] }` validation (`validateRatingRequest.js`) + live/coming-soon `metricCatalog.js` (coming-soon hard-400), `timeBoundary` now tags `localHour`, and the wrap-gated **night-stitch** (nocturnal activities bucket by night; per-activity `days.length`). Full suite green (106); doc-slice migrated, §2 Phase-2 rows reconciled (no Phase-2 drift remains). Phase 1 + Phase 2 are now merged into `pre-merge-main` (`--no-ff`, `ae3e906`). **Next: user-driven ultra-review of the rebuild, then the `pre-merge-main → main` merge.** Prior (2026-06-22): Phase 1 (7-day day-bucketed `days[]`/`timezone` output) implemented + merged. Prior (2026-06-20): ADR-0005 request schema pinned. Prior (2026-06-19): day-bucketing via provider IANA `timezone`, `flexi` horizon verified (168 = ceiling), B2 resolved.

This is the **"start here" dashboard** for the codebase. It tells you *where the project is right now* and links down to the detail. It does **not** restate decisions — it points to them, so it can't drift out of sync.

**Read order:** you should already have read [`CLAUDE.md`](../CLAUDE.md) and the glossary in [`CONTEXT.md`](CONTEXT.md) **before** this file. The terms below assume that vocabulary.

---

## 1. Truth rule — which doc to trust

| Doc | Authoritative for |
|---|---|
| [`CLAUDE.md`](../CLAUDE.md), [`CONTEXT.md`](CONTEXT.md) | **Code as it EXISTS now.** The backend through rebuild Phase 2. |
| [`personalization_grill.md`](personalization_grill.md), [`adr/`](adr/) | **Decisions of record.** The Phase 1/2 contract decisions (ADR-0002 → ADR-0005) are now **built**; the remainder is **decided but not yet built** — the deferred `GET /api/v1/metrics` route (ADR-0006) and the grill's personalization layer. |

The core contract and the code are now **in sync** — Phase 1/2 merged each doc-slice together with its code. Where the design-docs still lead the code, it is only the *unbuilt remainder* above (expected, not drift). Trust the code-docs for *what is*; trust the design-docs for *what's decided* (built or pending).

## 2. Drift table — terms/contract changing under the rebuild

| Thing | Current (in code) | Locked future | Migrates in | Source |
|---|---|---|---|---|
| **Activity** | **caller-supplied profile sent in the POST body; engine agnostic (`src/activities/*` removed) — migrated** | (now current) | **Phase 2 ✅ (branch)** | [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2 |
| **Forecast** | **7-day rolling, ≤168 provider-determined (`flexi` ~161–168) — migrated** | (now current) | **Phase 1 ✅ (branch)** | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), grill Q6 |
| **Index** | **0..N-1 (N ≤ 168) — migrated** | (now current) | **Phase 1 ✅ (branch)** | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) |
| **Lite / Pro** | **metric-access + quantity gating, client-enforced (no `-lite`/`-pro` activity variants) — migrated** | (now current) | **Phase 2 ✅ (branch)** | grill Q3 |
| **Display metrics** | **user-chosen (request field, echoed through) — migrated** | (now current) | **Phase 2 ✅ (branch)** | [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2 |
| **`/rating` contract** | **migrated (in + out):** `POST` body `{ lat, lon, activities[] }`, caller-supplied activities, atomic structured `{ errors[] }`; response `activities[].days[]` + top-level `timezone` (`hour` dropped) | (now current) | **out → Phase 1 ✅, in → Phase 2 ✅ (branch)** | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) (out), [ADR-0005](adr/0005-custom-activity-request-schema.md) (in) |

**All rows are now migrated on the rebuild branches** (Phase 1 = `rebuild/phase-1-day-bucketing`; Phase 2 = `rebuild/phase-2-custom-activities`) — [`CONTEXT.md`](CONTEXT.md)/[`CLAUDE.md`](../CLAUDE.md) describe the built state, so each row's "current" reality matches what those docs say (the drift tripwire holds). They land on `main` only when these branches merge through `pre-merge-main`. **"Migrates in"** names the phase whose *merge* carries each doc-slice (code + docs together, so `main` never sits in drift); the `/rating` row spanned both phases (response shape in Phase 1, request flip in Phase 2). No Phase-2 drift rows remain open.

## 3. Locked decisions (detail is in the linked source — not repeated here)

- No accounts; guest/local-first; iCloud sync; anon device id for push — [ADR-0001](adr/0001-no-accounts-guest-first.md), grill Q1
- Activity-agnostic engine; curated list → Templates — [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2
- Pro = premium metrics + quantity; client-enforced — grill Q3
- Pre-launch data: Air Quality + Marine swappable adapters — grill Q4
- Drop Supabase; one Node + Railway Postgres; append-only events at launch — grill Q5
- Forecast 7-day rolling, flat hours (count provider-determined, **168 = ceiling not count**); day-bucketed evaluation — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), grill Q6
- Provider-specifics stop at the adapter boundary; no provider horizon baked into the contract; never fabricate hours — [CONTEXT.md](CONTEXT.md) (Adapter), [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md)
- Day-bucketed `/rating` wire shape: `activities[].days[]`, day-0 card, dense null days, no top-level pointer — [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)
- Day bucketing = **forecast-location local calendar days** (provider IANA `timezone` + time-boundary module; `dayIndex` 0..6 or 0..7, today/tail partial, `startIndex`/`endIndex` global); response carries top-level `timezone`; client renders in that zone — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)
- Card default = `days[0]`, **client-side soonest-actionable fallback** (today if windowed, else earliest non-null day by name, else "no window in 7 days"); soonest not best; no server field; Daily Digest stays day-0 — [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)
- **Request schema (input twin of B2):** POST `{ lat, lon, activities[] }`; per-activity display-superset/threshold-subset; half-open local-hour window (wrap = nocturnal); atomic structured-array 400; **coming-soon/unknown metric = hard 400** (false-Perfect guard); tier/quantity client-enforced, not server-side — [ADR-0005](adr/0005-custom-activity-request-schema.md)
- Wrap-gated **night-stitch** = one controlled cross-midnight exception (opt-in, bounded); nocturnal buckets by *night* so `days.length` is **per-activity** (no cross-activity equality) — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) + [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) amendments
- Notification type follows activity shape, not tier (Daily Digest / Window Watch) — grill "Notification / CRON model"
- iOS shape: 5 surfaces / 8 screens, no bottom bar — grill Q6–Q9, "Page inventory — final (v1)"

## 4. Open blockers & flags (from the grill audit, 2026-06-18)

- **B2 — RESOLVED (2026-06-19).** Day-bucketed `/rating` wire shape pinned → [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) (read `days.length` per activity; never assume 7). **No longer blocks iOS #5a.** History → [STATUS_LOG.md](STATUS_LOG.md).
- **Provider verification — Meteosource base DONE (2026-06-19)** → [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) (`flexi` ~164 clean hourly; **168 = ceiling, not count**; point `fetch.js` at `/api/v1/flexi/point`). History → [STATUS_LOG.md](STATUS_LOG.md). **Open:** verify Air Quality + Marine sources return clean hourly across the same horizon — each when its adapter lands, not before.
- **"Stateless backend" is path-specific.** True for the `/rating` path; the #6c push store holds a tier flag and enforces/stops Pro cron jobs. Reword when the contract migrates. — grill Q3 / Q5 / Notification model.
- **Stored-activity metric flip — server side now built; CLIENT reconciliation still undesigned.** The **coming-soon hard-400** is live ([ADR-0005](adr/0005-custom-activity-request-schema.md) + `src/weather/metricCatalog.js`): a threshold/display on a non-live metric is rejected, and because validation is **atomic**, one stale stored activity would **reject the whole `/rating` request** (the entire dashboard fails to render, not just that card). The remaining gap is **client-side**: a reconciliation rule (detect the flip against the served catalog, prompt/strip before POSTing). Sharper now that the structured `{ errors[] }` `path` identifies the offending activity, though a stable error-`code` enum is still wanted (below). — grill Q2 #2 + ADR-0005 atomicity.
- **`GET /api/v1/metrics` route — unpinned (needs ADR-0006).** The catalog **data** now exists server-side (`src/weather/metricCatalog.js`, live vs coming-soon), but the **route** (response envelope, error shape, per-region availability, refresh/TTL) is in no ADR. Blocks the authoring metric-picker. **Deferred (cleanly parallel — see §5).** The route would read from the existing `metricCatalog.js`. — grill Q2(a)/Q7 + 2026-06-20 audit.
- **#5b/Phase-2 prerequisites surfaced by the 2026-06-20 audit (none block #5a-core):** (a) **ADR-0005 error-`code` enum** — error messages are English prose; the atomic metric-flip recovery needs stable codes for the client to find the offending activity; (b) **seed Template threshold values** — the onboarding seed activities' actual numbers are unpinned (needed once the client authors/POSTs). Both ride with authoring/Phase-2, not #5a-core.

## 5. Build-readiness

> **▶ NEXT (start here, fresh session):** **Phase 2 is implemented on `rebuild/phase-2-custom-activities` (code + code-docs, pre-merge).** The `GET→POST` contract flip, caller-supplied `evaluateAll(hours, activities)`, ADR-0005 validation + `metricCatalog.js`, and the wrap-gated **night-stitch** are all built; `src/activities/*` removed; full suite green (106). Code-docs migrated for the Phase-2 slice and §2 reconciled (no Phase-2 drift rows remain). Phase 2 is now merged into `pre-merge-main` with `--no-ff` (`ae3e906`; Phase 1 earlier). **Next: the user runs the full ultra-review of the rebuild, then drives the `pre-merge-main → main` merge.** Branch flow: phase branches → `pre-merge-main` (integration; ultra-review) → `main`. **Cleanly parallel / not yet built:** `GET /api/v1/metrics` route (needs ADR-0006; reads the existing `metricCatalog.js`); client-side stale-activity reconciliation (§4); ADR-0005 error-`code` enum; seed Template threshold values (#5b). **Known limitation (not a bug):** DST *inside* a time-of-day window is untested (Asia/Dubai has no DST) — do not assert DST-correctness for windows.

- **Current backend (through #10):** stable, tested, buildable.
- **iOS #5a (core app):** **scoped & unblocked (2026-06-20).** Decision: **#5a ships core read-only first** — decode `days[]`/`timezone`, render card + soonest-actionable fallback + 7-day timeline. **Note (post-Phase-2):** the backend is now **POST-only** with **caller-supplied** activities — there is no curated/hardcoded list to read against, so even the read-only #5a must encode a `POST` body (seed Templates client-side). Full authoring UI + metric-picker still defer to the **#5b wave** (resolves grill PENDING #2). Wire shape pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) incl. the 2026-06-20 amendments (per-activity `days.length`, nocturnal tail/label, per-hour shape + `hour` dropped); decode against variable-length `days[]` (read `days.length` per activity; never hardcode 7). **Night-stitch is now live** (Phase 2): a nocturnal Activity (wrapped `window`) returns stitched cross-midnight nights, so the Stargazing card no longer fragments at calendar-midnight.
- **Timeline detail (screen #2):** unblocked for base weather — Meteosource `flexi` 7-day hourly verified. (Marine/AQ fields on the timeline wait for those adapters.)

### Phase 1 — work items (output side: `days[]`/`timezone` behind GET, activities still hardcoded)

Resumability checklist for cold-session pickup. Pointers to ADR sections, not restatements — read the ADR for the detail.

- [x] `fetch.js` → `/api/v1/flexi/point` + `timezone=auto` ([ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md))
- [x] `parse.js`: `slice(0, FORECAST_HOURS)` — 168 ceiling, last day partial, never fabricate hours ([ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md))
- [x] time-boundary module (`src/weather/timeBoundary.js`): `(utc instant, IANA zone) → localDay`, tags each hour (internal, not on wire); also `zonedWallTimeToUtcIso` for the local→UTC fetch wrinkle ([ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) worked 8-bucket example)
- [x] `evaluateAll` output → per-activity `days[]` (global indices) + top-level `timezone`; signature **stays** `evaluateAll(hours)` (activities hardcoded until Phase 2) ([ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md))
- [x] rewrite affected tests; **golden snapshot hand-verified against [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)** + a partial-day-0 route fixture (variable-length buckets, non-24 offset). The snapshot is Phase 1's executable spec.
- [x] **at phase close:** migrated the `days[]`/`timezone`/horizon doc-slice of CONTEXT/CLAUDE (code + docs together, this commit); §2 reconciled

**Phase 1: complete; merged into `pre-merge-main`.** (Its dormant night-stitch limitation is resolved by Phase 2, below.)

### Phase 2 — work items (request flip + caller-supplied engine + night-stitch)

Resumability checklist. Built on `rebuild/phase-2-custom-activities` to [ADR-0005](adr/0005-custom-activity-request-schema.md) + the ADR-0003/0004 night-stitch amendments. Full suite green (106).

- [x] `src/weather/metricCatalog.js` — live vs coming-soon metric sets (validation source of truth; the deferred `GET /api/v1/metrics` will read it)
- [x] `src/routes/validateRatingRequest.js` — atomic, structured ADR-0005 §6 validation (full rejection set; unknown/coming-soon rejected in both `displayMetrics` and `thresholds`)
- [x] `routes/rating.js` → `POST`, body `{ lat, lon, activities[] }`, **validate-before-`getWeather`**, `evaluateAll(hours, activities)`, uniform `{ errors[] }` envelope across 400/502/500, strips `localDay`/`localHour`
- [x] `decision/evaluateAll.js` → caller-supplied; bucketing **inside** the activity loop; same-day window filter + wrapped **night-stitch** (orphan-morning drop, evening-day `dayIndex`, one midnight) — global indices hand-verified
- [x] `timeBoundary.js` → also tags `localHour`
- [x] deleted `src/activities/*`; repointed `cli.js` to an inline sample
- [x] reworked tests (golden snapshot for POST + night-stitch wire); added `metricCatalog` + `validateRatingRequest` suites
- [x] **at phase close:** migrated the Phase-2 doc-slice of CONTEXT/CLAUDE (this commit); §2 reconciled

**Phase 2: complete on the branch; pending the `--no-ff` merge into `pre-merge-main`** (then ultra-review, user-driven).

---

## History

Full chronological edit history → [STATUS_LOG.md](STATUS_LOG.md). This file holds only current state + forward pointers; the latest delta at a glance is the **Last updated** banner at the top.
