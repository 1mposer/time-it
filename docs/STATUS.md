# STATUS — project orientation hub

> **Last updated: 2026-06-20** — Custom-activity request schema grilled & pinned ([ADR-0005](adr/0005-custom-activity-request-schema.md)): POST `{ lat, lon, activities[] }`, display-superset/threshold-subset, half-open local-hour window, wrap-gated nocturnal stitch, coming-soon-metric hard-400, atomic structured errors. Triggered amendments to ADR-0003 (night-stitch) + ADR-0004 (`days.length` per-activity). **Phase-2 gate cleared.** Prior (2026-06-19): partial-day-0 card rule, day-bucketing via provider IANA `timezone`, `flexi` horizon verified (168 = ceiling), B2 resolved.

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
| **`/rating` contract** | `GET`, singular `rating`/window, 5 activities | `POST`, body `{ lat, lon, activities[] }` in / `activities[].days[]` out (local-calendar days, day-0 card, top-level `timezone`), caller-supplied activities | [ADR-0002](adr/0002-activity-agnostic-engine.md), [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) (out), [ADR-0005](adr/0005-custom-activity-request-schema.md) (in) |

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
- **Request schema (input twin of B2):** POST `{ lat, lon, activities[] }`; per-activity display-superset/threshold-subset; half-open local-hour window (wrap = nocturnal); atomic structured-array 400; **coming-soon/unknown metric = hard 400** (false-Perfect guard); tier/quantity client-enforced, not server-side — [ADR-0005](adr/0005-custom-activity-request-schema.md)
- Wrap-gated **night-stitch** = one controlled cross-midnight exception (opt-in, bounded); nocturnal buckets by *night* so `days.length` is **per-activity** (no cross-activity equality) — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) + [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) amendments
- Notification type follows activity shape, not tier (Daily Digest / Window Watch) — grill "Notification / CRON model"
- iOS shape: 5 surfaces / 8 screens, no bottom bar — grill Q6–Q9, "Page inventory — final (v1)"

## 4. Open blockers & flags (from the grill audit, 2026-06-18)

- **B2 — RESOLVED (2026-06-19).** Day-bucketed `/rating` wire shape pinned → [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) (read `days.length` per activity; never assume 7). **No longer blocks iOS #5a.** History → [STATUS_LOG.md](STATUS_LOG.md).
- **Provider verification — Meteosource base DONE (2026-06-19)** → [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) (`flexi` ~164 clean hourly; **168 = ceiling, not count**; point `fetch.js` at `/api/v1/flexi/point`). History → [STATUS_LOG.md](STATUS_LOG.md). **Open:** verify Air Quality + Marine sources return clean hourly across the same horizon — each when its adapter lands, not before.
- **"Stateless backend" is path-specific.** True for the `/rating` path; the #6c push store holds a tier flag and enforces/stops Pro cron jobs. Reword when the contract migrates. — grill Q3 / Q5 / Notification model.
- **Stored-activity metric flip — undesigned, now sharper under [ADR-0005](adr/0005-custom-activity-request-schema.md).** An activity thresholding a metric that later flips available→coming-soon now hits the **coming-soon hard-400** — and because validation is **atomic**, one stale stored activity would **reject the whole `/rating` request** (the entire dashboard fails to render, not just that card). Engine null-fail mitigates the *evaluation* hazard, but the *request-rejection* blast radius is new and unplanned: needs a client-side reconciliation rule (detect the flip against the served catalog, prompt/strip before POSTing) or a server policy carve-out. — grill Q2 #2 + ADR-0005 atomicity.
- **`GET /api/v1/metrics` route — unpinned (needs ADR-0006).** Only a catalog-*item* shape is sketched (grill Q7); the **route** (response envelope, error shape, per-region availability, refresh/TTL) is in no ADR. Blocks the authoring metric-picker. **Deferred to the #5b/Phase-2 wave** (not an #5a-core blocker — see §5 scope decision). Supersedes the narrower "refresh policy missing" framing. — grill Q2(a)/Q7 + 2026-06-20 audit.
- **#5b/Phase-2 prerequisites surfaced by the 2026-06-20 audit (none block #5a-core):** (a) **ADR-0005 error-`code` enum** — error messages are English prose; the atomic metric-flip recovery needs stable codes for the client to find the offending activity; (b) **seed Template threshold values** — the onboarding seed activities' actual numbers are unpinned (needed once the client authors/POSTs). Both ride with authoring/Phase-2, not #5a-core.

## 5. Build-readiness

> **▶ NEXT (start here, fresh session):** the request-schema grill is **DONE → [ADR-0005](adr/0005-custom-activity-request-schema.md)** (Phase-2 gate cleared). Begin implementation. **Phase 1** (168-ceiling slice + location-local day-buckets + `days[]`/`timezone` wire, behind the existing GET, hardcoded activities kept — fully specified by ADR-0003/0004, needs no schema) → **Phase 2** (the `GET→POST` contract flip + `evaluateAll(hours,activities)`, built to ADR-0005; folds in the wrap-gated night-stitch per the ADR-0003 amendment) → **Job B** (migrate CONTEXT/CLAUDE glossary+contract once code lands). Implement the coupled core as **one stream, not a sub-agent fan-out** (only `GET /api/v1/metrics` is cleanly parallel). Work happens on `main`.

- **Current backend (through #10):** stable, tested, buildable.
- **iOS #5a (core app):** **scoped & unblocked (2026-06-20).** Decision: **#5a ships core read-only first** — decode `days[]`/`timezone`, render card + soonest-actionable fallback + 7-day timeline against seeded/curated activities. **Authoring + POST encode + metric catalog defer to the #5b/Phase-2 wave** (resolves grill PENDING #2, "v1-vs-fast-follow", for the iOS axis). Wire shape pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) incl. the 2026-06-20 amendments (per-activity `days.length`, nocturnal tail/label, per-hour shape + `hour` dropped); decode against variable-length `days[]` (read `days.length` per activity; never hardcode 7). (Backend still ships the old `GET`/24h/singular-rating shape — Phase 1 makes the live API match this contract.) **Known #5a-core limitation:** Phase 1 has no window support, so night-stitch is dormant — the curated **Stargazing** card shows *fragmented* nocturnal windows (split at calendar-midnight) until Phase 2. Deliberate, not a bug.
- **Timeline detail (screen #2):** unblocked for base weather — Meteosource `flexi` 7-day hourly verified. (Marine/AQ fields on the timeline wait for those adapters.)

---

## History

Full chronological edit history → [STATUS_LOG.md](STATUS_LOG.md). This file holds only current state + forward pointers; the latest delta at a glance is the **Last updated** banner at the top.
