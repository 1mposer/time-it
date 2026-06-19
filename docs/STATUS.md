# STATUS — project orientation hub

> **Last updated: 2026-06-19** — Card partial-day-0 rule settled (client-side soonest-actionable fallback; ADR-0004). Earlier today: day-bucketing = location-local calendar days via provider IANA `timezone`, `flexi` horizon verified, 168 reframed as a ceiling, B2 resolved.

This is the **"start here" dashboard** for the codebase. It tells you *where the project is right now* and links down to the detail. It does **not** restate decisions — it points to them, so it can't drift out of sync.

**Read order:** you should already have read [`CLAUDE.md`](../CLAUDE.md) and the glossary in [`CONTEXT.md`](CONTEXT.md) **before** this file. The terms below assume that vocabulary.

---

## 1. Truth rule — which doc to trust

| Doc | Authoritative for |
|---|---|
| [`CLAUDE.md`](../CLAUDE.md), [`CONTEXT.md`](CONTEXT.md) | **Code as it EXISTS now.** The shipped backend (through Issue #10). |
| [`personalization_grill.md`](personalization_grill.md), [`adr/`](adr/) | **Design as DECIDED but not yet built.** The target the rebuild aims at. |

When these two disagree, that is **expected, not a bug** — the design is ahead of the code. Trust the code-docs for *what is*; trust the design-docs for *what we're building toward*.

## 2. Drift table — terms/contract changing under the rebuild

| Thing | Current (in code) | Locked future | Source |
|---|---|---|---|
| **Activity** | hardcoded list (`src/activities/*`) | user-authored profile; engine agnostic | [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2 |
| **Forecast** | 24 hourly entries | 7-day rolling, **≤168** provider-determined (Meteosource `flexi` ~164) | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), grill Q6 |
| **Index** | 0–23 | 0..N-1 (N ≤ 168) | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) |
| **Lite / Pro** | activity tiers (`-lite`/`-pro`) | metric-access + quantity gating | grill Q3 |
| **Display metrics** | backend-decided | user-chosen | [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2 |
| **`/rating` contract** | `GET`, singular `rating`/window, 5 activities | `POST`, `activities[].days[]` (local-calendar days, day-0 card, top-level `timezone`), caller-supplied activities | [ADR-0002](adr/0002-activity-agnostic-engine.md), [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) |

Term definitions in [`CONTEXT.md`](CONTEXT.md) still describe the **current** column — they migrate to the **future** column only when the code lands (deliberate; avoids glossary/code drift).

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
- Notification type follows activity shape, not tier (Daily Digest / Window Watch) — grill "Notification / CRON model"
- iOS shape: 5 surfaces / 8 screens, no bottom bar — grill Q6–Q9, "Page inventory — final (v1)"

## 4. Open blockers & flags (from the grill audit, 2026-06-18)

- **B2 — RESOLVED (2026-06-19).** The day-bucketed `/rating` wire shape is now pinned: flat 7-entry `activities[].days[]`, singular top-level `rating`/window removed (no pointer), dense null days (`{ dayIndex, rating: null }`, window triplet absent), card defaults to `days[0]`. **No longer blocks iOS #5a.** — [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).
- **Provider verification — Meteosource DONE (2026-06-19).** Live probe: `flexi` tier returns ~164 clean hourly entries, no degradation across the 7-day horizon (`/free/` caps at 24). Horizon premise holds; **168 reframed as a ceiling, not a count.** Phase 1 unblocked. Implementation note: point `fetch.js` at `/api/v1/flexi/point`. **Remaining:** verify Air Quality + Marine sources return clean hourly across the same horizon — each at the point its adapter lands, not before. — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md).
- **"Stateless backend" is path-specific.** True for the `/rating` path; the #6c push store holds a tier flag and enforces/stops Pro cron jobs. Reword when the contract migrates. — grill Q3 / Q5 / Notification model.
- **Stored-activity metric flip — undesigned.** No decision for an activity that thresholds on a metric which later flips available→coming-soon (reopens the false-Perfect hazard; engine null-fails mitigates but it's unplanned). — grill Q2 #2.
- **Metric-catalog refresh policy — missing.** No client re-fetch/TTL rule for `GET /api/v1/metrics`. — grill Q2(a).
- **Grill self-defects fixed in-place 2026-06-18:** handoff line 37 falsely listed the day-bucket result shape as "done" (it's B2, above); Q3.i "Template-derived never lock" clarified to "never lock *on the quantity cap*."

## 5. Build-readiness

> **▶ NEXT (start here, fresh session):** grill the **custom-activity request schema** → **ADR-0005** — the input-side twin of B2 and the one gate on Phase 2 (GET→POST). The *fields* are already decided (ADR-0002 + grill lines 70/144/191); this is a short **serialization + validation** grill (request envelope, per-metric threshold encoding, error rules), not open design. Then implement **Phase 1** (168-ceiling slice + location-local day-buckets + `days[]`/`timezone` wire, behind the existing GET, hardcoded activities kept — fully specified, needs no schema) → **Phase 2** (the contract flip) → **Job B** (migrate CONTEXT/CLAUDE glossary+contract once code lands). Implement the coupled core as **one stream, not a sub-agent fan-out** (only `GET /api/v1/metrics` is cleanly parallel). Work happens on branch `ARD-test`.

- **Current backend (through #10):** stable, tested, buildable.
- **iOS #5a (core app):** **unblocked** — wire shape pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md); decoder can be written against the 7-entry `days[]`. (Backend still ships the old `GET`/24h/singular-rating shape — the rebuild to ADR-0002/0003/0004 is the work that makes the live API match this contract.)
- **Timeline detail (screen #2):** unblocked for base weather — Meteosource `flexi` 7-day hourly verified. (Marine/AQ fields on the timeline wait for those adapters.)

---

## Edit log

- **2026-06-18** — Created. Drift table + locked-decisions index + audit blockers (B2, provider-verify, stateless wording, metric-flip, catalog refresh). Paired with: CONTEXT.md/CLAUDE.md routing banners, deletion of three empty `docs/agents/*.md` orphans, two in-place grill corrections (line 37, Q3.i).
- **2026-06-19** — B2 resolved. Added [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) pinning the day-bucketed `/rating` wire shape (flat 7-entry `days[]`, day-0 card, dense null days, no top-level pointer). Flipped §4 B2 blocker→resolved, §5 iOS #5a blocked→unblocked, drift-table `/rating` row, locked-decisions index. Paired with grill line 37 update.
- **2026-06-19** — Provider verification done (Meteosource `flexi` ~164 clean hourly). Reframed ADR-0003 + ADR-0004: **168 is a ceiling, not a count** — horizon provider-determined, last day partial, decoder/snapshot must not hardcode 168/7, no fabricated hours. Added adapter-boundary principle to CONTEXT.md (Adapter term). Updated drift table (Forecast/Index rows), locked-decisions (+horizon + adapter-boundary), §4 provider flag DONE, §5 timeline unblocked.
- **2026-06-19** — Day-bucketing rule settled: **location-local calendar days**, not `floor(index/24)` blocks. Timezone = provider's IANA `timezone` field (Meteosource `timezone=auto`), normalised at the adapter boundary; a new **time-boundary module** tags each hour's `localDay`; engine groups by it. `dayIndex` = 0-based local-calendar-day ordinal (0..6 or 0..7; today + tail partial), `days.length` NOT a closed form over `hours.length`; `startIndex`/`endIndex` stay global; `localDay` internal (not on wire); response gains top-level `timezone`; client renders in that zone. Amended ADR-0003 (rule + worked 8-bucket example + fetch wrinkle + UTC-instant landmine), ADR-0004 (killed false `days.length` formula, +`timezone`, +three pins), CONTEXT (sibling time-boundary principle + Forecast-start rendering note), this drift table + locked-decisions. **Open:** partial-day-0 card rule (parked); custom-activity request schema (Phase-2 gate, unchanged).
- **2026-06-19** — Partial-day-0 card rule settled (was parked). Card = `days[0]` with a **client-side soonest-actionable fallback**: today if it has a window, else the earliest non-null day (labeled by name), else "No window in the next 7 days." Soonest, *not* best (does not reopen `bestDayIndex`); pure client display rule, **no wire change**; Daily Digest stays strictly day-0. Amended ADR-0004 sub-decision 4 + locked-decisions here. **Open now:** custom-activity request schema (Phase-2 gate).
- **2026-06-19** — Session close-out: added the **▶ NEXT** pointer to §5 (request-schema grill → ADR-0005, then Phase 1 → Phase 2 → Job B; implement coupled core as one stream). Boundary/horizon design fully settled & committed; next work starts in a clean session on branch `ARD-test`.
