# STATUS — now / next / blocked

> **Last updated: 2026-08-19** — the owner-side APNs prerequisites landed (bundle-ID rename + `aps-environment` entitlement, ROADMAP item 4; release build on a real device), unblocking #6c/#6d live acceptance. Events of record: [ROADMAP](issues/ROADMAP.md). This file is deliberately one screen: a snapshot only.

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
| Now / next / blocked snapshot | this file |
| Vendor API behavior | [`API_documentation/`](API_documentation/) |
| Figma addresses, workflow rules, gate state | [`design/FIGMA.md`](design/FIGMA.md) |
| Design values (tokens, palette, geometry) | **never a doc** — the Figma file (design truth) + code (`Theme.swift`, views — shipped truth) |
| Private operational facts | `OWNER_NOTES.local.md` (git-ignored) |

Completed specs (in [`issues/completed/`](issues/completed/)) are historical records: bannered, never edited again.

## 2. Now / next / blocked

- **NOW:** **#6c/#6d live acceptance** ([checklist: push-client spec §6](issues/current/implement-spec-push-client.md), ROADMAP item 8) — **unblocked 2026-08-19**: item 4 (rename) + the APNs entitlement are done and the release build is on a real device. First box: verify the toggle-on `devices` row lands on Railway. **Awaiting owner review (flagged, not decided):** spec 14's I2 (all-dormant header hides its weather rows — proposal) and I3 (provisional phrase strings).
- **NEXT (ship order — ROADMAP has the full table):** live acceptance boxes (§6) → **TestFlight** (item 9, owner ops — App Store Connect, archive/upload, `NODE_ENV=production` on Railway); its first build carries ROADMAP item 10 (beta feedback — server route ✅, iOS client next).
- **BLOCKED:** nothing hard-blocks live acceptance; the beta frames were owner-approved 2026-08-19 ([FIGMA.md §8](design/FIGMA.md)), so item 10's iOS client is in build; TestFlight (item 9) is owner ops after acceptance.

## 3. Standing flags (not blockers)

- **Known limitations (recorded, accepted):** DST *inside* a time-of-day window is untested (Asia/Dubai has no DST) — do not assert DST-correctness for windows. Half-hour zones (e.g. +05:30) render `ha`-style clock labels :30 off in both the iOS `TimeDeriver` and the server `jobs/labels.js`.
- **Client mirrors:** the client deliberately re-implements slices of server logic — read [ADR-0007](adr/0007-client-side-mirrors.md) before touching threshold semantics on either side.
- **UI is Figma-first:** frames precede code — decision of record: [ADR-0008](adr/0008-figma-first-ui-gate.md); frame backlog: [FIGMA.md §7](design/FIGMA.md).
- **Deferred-with-conditions:** the list + promote conditions live in [ROADMAP §Deferred](issues/ROADMAP.md).

## 4. Built state

Per-item build status: [ROADMAP](issues/ROADMAP.md) (ship path + completed — the single home). Architecture as it exists: [CLAUDE.md](../CLAUDE.md).

*History: `git log`. (STATUS_LOG.md was deleted 2026-08-10 — git history keeps it.)*
