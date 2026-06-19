# The day-bucketed `/rating` response is a flat 7-entry `days[]` per activity, day-0 default, dense null days

The `/rating` response keeps its top-level container — `{ forecastStart, activities[], hours[] }` — with `hours[]` growing from 24 to **168** entries (`index` 0..167, per [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md)). The change B2 pins is the **per-activity result shape**: the previous singular top-level `rating` + window triplet (`startIndex`/`endIndex`/`duration`) is **removed** and replaced by a `days[]` array of **exactly 7** day-results.

```json
{
  "forecastStart": "2026-06-19T14:00:00Z",
  "activities": [
    {
      "activityId": "boat-fishing-pro",
      "label": "Boat Fishing Pro",
      "displayMetrics": ["temp"],
      "days": [
        { "dayIndex": 0, "rating": "perfect", "startIndex": 3,   "endIndex": 9,   "duration": 6 },
        { "dayIndex": 1, "rating": "good",    "startIndex": 28,  "endIndex": 31,  "duration": 3 },
        { "dayIndex": 2, "rating": null },
        { "dayIndex": 3, "rating": null },
        { "dayIndex": 4, "rating": "perfect", "startIndex": 99,  "endIndex": 108, "duration": 9 },
        { "dayIndex": 5, "rating": null },
        { "dayIndex": 6, "rating": "good",    "startIndex": 150, "endIndex": 153, "duration": 3 }
      ]
    }
  ],
  "hours": [ /* 168 entries, index 0..167 */ ]
}
```

**Four sub-decisions, pinned:**

1. **Container — flat `activities[].days[]`, always 7 entries, `days[i].dayIndex === i`.** Dense, not sparse: a day with no qualifying window still occupies its slot, so the client indexes by position without scanning `dayIndex`. There is no nested `week` object — "day" stays derived (`floor(index / 24)`), consistent with [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md)'s flat-hours/derived-grouping rule.

2. **The singular top-level `rating`/window is removed — no top-level pointer.** Each activity carries only `activityId`, `label`, `displayMetrics`, `days`. The dashboard card reads `days[0]`; the timeline reads `days[0..6]`. One source of truth, zero derived or duplicated fields, nothing to drift.

3. **Null-day — object present, `rating: null`, window triplet absent.** A non-qualifying day is `{ "dayIndex": n, "rating": null }` with `startIndex`/`endIndex`/`duration` **omitted** — the exact convention the current contract uses for a null-rated activity, applied one level down. The iOS decoder keeps modeling the window fields as optional; nothing new to learn.

4. **Card default — `days[0]` ("today").** "Best day this week" is a timeline-drill-down concern, not a wire field. The server does not compute or expose a `bestDayIndex`.

Chosen because day-0-default + dense + no-pointer is the minimal shape that carries no redundant state. ADR-0003 introduced day-bucketing precisely because "the dashboard card wants *today*" while an unbounded search "returns windows days away" — so day 0 *is* the card's natural default, and a server-computed best-day pointer would add a tie-break rule and a derived field for a view (the timeline) that already has every day in hand. Dense indexing trades a marginal payload saving (the response is already ~7× larger from the hours bump) for the guarantee that `days[dayIndex]` is positional, which keeps the iOS decoder and the golden snapshot simple.

Rejected alternatives: a server `bestDayIndex` pointer (adds a derived field + earliest-wins tie-break rule the client can compute itself when it wants a "best this week" badge); a sparse `days[]` carrying only qualifying days (forces every consumer to key off `dayIndex`, loses positional access, saves little against the 168-hour payload); keeping a duplicated singular `rating`/window alongside `days[]` (two representations of the same verdict — the drift hazard this whole audit exists to remove); a nested `week { days: [...] }` object (rejected already in [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md) — a box around seven boxes).

**Consequences:** the per-day-result key order is pinned `dayIndex, rating, startIndex, endIndex, duration`, and the activity-object key order is `activityId, label, displayMetrics, days` — the golden snapshot in `tests/server/rating.test.js` reworks to assert these plus `days.length === 7` and `hours.length === 168`. `evaluateAll` returns the day-bucketed result described in [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md); the route layer shapes it into the wire form above. The iOS #5a decoder is now unblocked — it decodes `days[]` as a fixed 7-element array with an optional window per element and reads `days[0]` for the card. The **Daily Digest** (per ADR-0003) slices day 0 — i.e. reads `days[0]` — before notifying. The POST request body (`{ lat, lon, activities }`) and its validation errors are **not** decided here; that is [ADR-0002](0002-activity-agnostic-engine.md)'s domain. Error mapping (400/502/500) is unchanged.

Recorded because this is the contract iOS #5a decodes against (reversible only with another versioned bump), it resolves audit blocker **B2**, and a future reader will ask why each activity exposes seven day-results with no top-level summary and why null days keep their slot rather than dropping out.
