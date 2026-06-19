# STATUS — project orientation hub

> **Last updated: 2026-06-19** — B2 resolved: day-bucketed `/rating` wire shape pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).

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
| **Forecast** | 24 hourly entries | 168 / 7-day rolling | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), grill Q6 |
| **Index** | 0–23 | 0–167 | [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) |
| **Lite / Pro** | activity tiers (`-lite`/`-pro`) | metric-access + quantity gating | grill Q3 |
| **Display metrics** | backend-decided | user-chosen | [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2 |
| **`/rating` contract** | `GET`, singular `rating`/window, 5 activities | `POST`, `activities[].days[]` (7-entry, day-0 card), caller-supplied activities | [ADR-0002](adr/0002-activity-agnostic-engine.md), [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) |

Term definitions in [`CONTEXT.md`](CONTEXT.md) still describe the **current** column — they migrate to the **future** column only when the code lands (deliberate; avoids glossary/code drift).

## 3. Locked decisions (detail is in the linked source — not repeated here)

- No accounts; guest/local-first; iCloud sync; anon device id for push — [ADR-0001](adr/0001-no-accounts-guest-first.md), grill Q1
- Activity-agnostic engine; curated list → Templates — [ADR-0002](adr/0002-activity-agnostic-engine.md), grill Q2
- Pro = premium metrics + quantity; client-enforced — grill Q3
- Pre-launch data: Air Quality + Marine swappable adapters — grill Q4
- Drop Supabase; one Node + Railway Postgres; append-only events at launch — grill Q5
- Forecast 7-day / 168 flat hours; day-bucketed evaluation — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), grill Q6
- Day-bucketed `/rating` wire shape: 7-entry `activities[].days[]`, day-0 card, dense null days, no top-level pointer — [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)
- Notification type follows activity shape, not tier (Daily Digest / Window Watch) — grill "Notification / CRON model"
- iOS shape: 5 surfaces / 8 screens, no bottom bar — grill Q6–Q9, "Page inventory — final (v1)"

## 4. Open blockers & flags (from the grill audit, 2026-06-18)

- **B2 — RESOLVED (2026-06-19).** The day-bucketed `/rating` wire shape is now pinned: flat 7-entry `activities[].days[]`, singular top-level `rating`/window removed (no pointer), dense null days (`{ dayIndex, rating: null }`, window triplet absent), card defaults to `days[0]`. **No longer blocks iOS #5a.** — [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).
- **Provider verification — precondition.** Confirm Meteosource + Air Quality + Marine return clean *hourly* data across all 7 days before the 168 horizon is final. **Blocks timeline screen #2** if data degrades past 48–72h. — [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md).
- **"Stateless backend" is path-specific.** True for the `/rating` path; the #6c push store holds a tier flag and enforces/stops Pro cron jobs. Reword when the contract migrates. — grill Q3 / Q5 / Notification model.
- **Stored-activity metric flip — undesigned.** No decision for an activity that thresholds on a metric which later flips available→coming-soon (reopens the false-Perfect hazard; engine null-fails mitigates but it's unplanned). — grill Q2 #2.
- **Metric-catalog refresh policy — missing.** No client re-fetch/TTL rule for `GET /api/v1/metrics`. — grill Q2(a).
- **Grill self-defects fixed in-place 2026-06-18:** handoff line 37 falsely listed the day-bucket result shape as "done" (it's B2, above); Q3.i "Template-derived never lock" clarified to "never lock *on the quantity cap*."

## 5. Build-readiness

- **Current backend (through #10):** stable, tested, buildable.
- **iOS #5a (core app):** **unblocked** — wire shape pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md); decoder can be written against the 7-entry `days[]`. (Backend still ships the old `GET`/24h/singular-rating shape — the rebuild to ADR-0002/0003/0004 is the work that makes the live API match this contract.)
- **Timeline detail (screen #2):** blocked on provider verification.

---

## Edit log

- **2026-06-18** — Created. Drift table + locked-decisions index + audit blockers (B2, provider-verify, stateless wording, metric-flip, catalog refresh). Paired with: CONTEXT.md/CLAUDE.md routing banners, deletion of three empty `docs/agents/*.md` orphans, two in-place grill corrections (line 37, Q3.i).
- **2026-06-19** — B2 resolved. Added [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) pinning the day-bucketed `/rating` wire shape (flat 7-entry `days[]`, day-0 card, dense null days, no top-level pointer). Flipped §4 B2 blocker→resolved, §5 iOS #5a blocked→unblocked, drift-table `/rating` row, locked-decisions index. Paired with grill line 37 update.
