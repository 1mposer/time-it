# STATUS — now / next / blocked

> **Last updated: 2026-08-24** — roadmap reset to the **onboarding-v2 activation phase** (grill ratified 2026-08-22; evidence + decisions: [research note](research/onboarding-tester-evidence-2026-08.md); predecessor archived: [ship-loop roadmap](issues/completed/roadmap-2026-08-ship-loop.md)). Production-lane push was proven end-to-end the same day; internal TestFlight testing live. Events of record: [ROADMAP](issues/ROADMAP.md). This file is deliberately one screen: a snapshot only.

**Read order:** [`CLAUDE.md`](../CLAUDE.md) → [`CONTEXT.md`](CONTEXT.md) → this file → [ROADMAP](issues/ROADMAP.md).

## 1. Truth rule — which doc owns which facts ([ADR-0009](adr/0009-tiered-doc-truth.md))

- A **volatile fact** is true *as of a date* — status, plan names, built/unbuilt, dates, in-flux decisions. Test: *can it become false just by the project moving forward?* It lives in **exactly one** home (table below); everywhere else links.
- A **contract fact** is a timeless rule — wire shapes, semantics, invariants; only a deliberate redesign changes it. It **may** be restated where readers need it inline (CLAUDE.md stays self-contained); the owner file is the reference of record, and changing one means sweeping its mirrors in the same change.

| Fact class | Home |
|---|---|
| Code as it exists (architecture, contracts, tests) | [`CLAUDE.md`](../CLAUDE.md) |
| Domain vocabulary | [`CONTEXT.md`](CONTEXT.md) |
| Decisions of record + rationale | [`adr/`](adr/) · [`personalization_grill.md`](personalization_grill.md) (frozen) |
| Per-item status, ship order, deferrals + promote conditions | [`issues/ROADMAP.md`](issues/ROADMAP.md) |
| User-research evidence (tester observations, persona rulings, grill records) | [`research/`](research/) |
| Now / next / blocked snapshot | this file |
| Vendor API behavior | [`API_documentation/`](API_documentation/) |
| Figma addresses, workflow rules, gate state | [`design/FIGMA.md`](design/FIGMA.md) |
| Design values (tokens, palette, geometry) | **never a doc** — the Figma file (design truth) + code (`Theme.swift`, views — shipped truth) |
| Private operational facts | `OWNER_NOTES.local.md` (git-ignored) |

Completed specs (in [`issues/completed/`](issues/completed/)) are historical records: bannered, never edited again.

## 2. Now / next / blocked

- **NOW — two parallel lanes:** (a) **onboarding-v2 design phase** ([ROADMAP items 11–12](issues/ROADMAP.md)): reference board approved + grey-box wireframes built (2026-08-24 — [FIGMA.md §9](design/FIGMA.md)); next: hi-fi frames → owner approval ([ADR-0008](adr/0008-figma-first-ui-gate.md) gate); (b) **finish the #6c/#6d acceptance boxes** ([checklist: push-client spec §6](issues/current/implement-spec-push-client.md), ROADMAP item 8) — remaining boxes are time-gated: digest 6–11 band, dedup silence, upgrade push, far-day, pruning, toggle-off re-verify under the never-erase code. **Awaiting owner review (flagged, not decided):** spec 14's I2 (all-dormant header hides its weather rows — proposal) and I3 (provisional phrase strings).
- **NEXT (ship order — ROADMAP has the full table):** onboarding-v2 **build** (item 13, Figma-gated) → **watched-session dad-test round** (item 14) → the item-9 external path unfreezes. Item 10's live boxes are ticked except the non-204/429 UX ([spec §5](issues/current/implement-spec-beta-feedback.md)).
- **BLOCKED:** nothing hard-blocked. The TestFlight **external path is held by owner ruling** (grill Q8, 2026-08-22 — [ROADMAP item 9](issues/ROADMAP.md)): every external step waits until onboarding v2 ships; a gate, not a blocker.

## 3. Standing flags (not blockers)

- **Known limitations (recorded, accepted):** DST *inside* a time-of-day window is untested (Asia/Dubai has no DST) — do not assert DST-correctness for windows. Half-hour zones (e.g. +05:30) render `ha`-style clock labels :30 off in both the iOS `TimeDeriver` and the server `jobs/labels.js`.
- **Client mirrors:** the client deliberately re-implements slices of server logic — read [ADR-0007](adr/0007-client-side-mirrors.md) before touching threshold semantics on either side.
- **UI is Figma-first:** frames precede code — decision of record: [ADR-0008](adr/0008-figma-first-ui-gate.md); completed frame passes: [FIGMA.md §7–§8](design/FIGMA.md); the open onboarding-v2 pass: [FIGMA.md §9](design/FIGMA.md).
- **Deferred-with-conditions:** the list + promote conditions live in [ROADMAP §Deferred](issues/ROADMAP.md).

## 4. Built state

Per-item build status: [ROADMAP](issues/ROADMAP.md) (ship path + completed — the single home). Architecture as it exists: [CLAUDE.md](../CLAUDE.md).

*History: `git log`. (STATUS_LOG.md was deleted 2026-08-10 — git history keeps it.)*
