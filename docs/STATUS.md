# STATUS — now / next / blocked

> **Last updated: 2026-11-18 — the ship phase is open ([ROADMAP item 23](issues/ROADMAP.md); [ship doc](issues/current/ship-phase.md)).** Build 11 is complete on `main`, not uploaded. 1.0 goes straight to App Store review with the current first run; onboarding v2 and the dad test follow 1.0 (owner rulings 2026-11-17/18). Events of record: [ROADMAP](issues/ROADMAP.md). This file is deliberately one screen: a snapshot only.

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

- **NOW — the ship phase ([ROADMAP item 23](issues/ROADMAP.md)):** the 1.0 ship gate. Owner rulings, the phase checklist and the Release Captain's ledger are in the [ship doc](issues/current/ship-phase.md). Still open with the owner from build 11: answer 12 from the current screenshot; the Instruments lane ([PR-011](post-release/items/PR-011-opening-hold-instruments.yaml)); the Xcode upload.
- **(was) NOW — build 10 and 11 rounds ([ROADMAP item 20](issues/ROADMAP.md), [lane plan](issues/current/build-10-lanes.md)):** five lanes merged to `main` overnight 2026-11-11→12 (LOCKDOWN, RERUN, CACHE, MANAGE, POLISH; final verifier green: 624 unit / 54 UI / 256 server, Release archive compiles). **Owner's next step: rule the morning page, run build 10 on the phone, upload from Xcode** (build 10 wipes every install's activities on first launch, owner ruling 2026-11-11). **2026-11-12:** the owner ran build 10 on the phone ("9/10, final touches") and gave the go for the remaining waves; three mini edits are on `main` (`87a2951`), SPEC is merged ([ROADMAP item 21](issues/ROADMAP.md) — owner rulings next on its page), FIXES (`455e5df`) and TRIAGE (`b3fd18f`) merged the same day — the round's eight lanes are on `main` (unit 639 / UI 60 / server 261 green on the FIXES branch at merge); THROTTLE stays "later" (owner's word). Owner ruled the fresh-eyes page 2026-11-12 → **Wave 5 running** (lanes COPY + CHIPS, [ROADMAP item 21](issues/ROADMAP.md)); parked work now lives as typed briefs in [docs/post-release](post-release/README.md) (`python3 tools/post_release_export.py` → the owner's sheet). **2026-11-13: Wave 5 closed** — COPY (`aeb209e`) and CHIPS (`6a9ee33`, owner ruled 01a 02a from the screenshot page) merged; wordmark ruled "Time it" and swept through the app copy (PR-009 done). **2026-11-15 (first interactive decisions page):** 04c round "+" (built), 05a, 06b → [PR-013](post-release/items/PR-013-card-text-at-ax-sizes.yaml), 07b → [PR-011](post-release/items/PR-011-opening-hold-instruments.yaml) scheduled, 08a upload after the rulings are built; the passed-day detail and the score-beside-Perfect question open **[ROADMAP item 22](issues/ROADMAP.md)** — the score & range rethink by an A/B agent loop (owner's method). The rethink loop ran 2026-11-15 (3 proposers → 5 raters → panel of 3): **Coach + four steals**, unanimous; owner rules on the verdict page linked from the ROADMAP row. Owner ruled 01 b and asked for a composite of their picks; three composites (A/B/C) are drawn — owner picks on the composite page linked from the ROADMAP row. **Owner ruled the composite page 2026-11-15:** a mix (C's card today + A's detail screens and tomorrow card), ring colour by score band, ring caption "Average" (the day score's user-facing name from now on), no own-hours on the card, card moves to tomorrow after the hours, keep "Best was …", "No good time" everywhere — details in ROADMAP row 22. The owner sent the edit list from the chosen-screens page (six screens, two new design rules: shared padding, squircle corners with outer r = inner r + padding) — the edit loop ran (A/B proposals → spacing judge → Opus final pass, light + dark) — owner ruled 2026-11-16: three small fixes (verdict line under the hour numbers, centred ring numeral, more overlay blur) → Final - Opus v2, and **the code lane starts: [build 11 — lane RETHINK](issues/current/build-11-rethink-lane.md)** (the owner then moves things by eye on the phone). **Lane RETHINK merged to `main` 2026-11-16 — build 11** (verifier green: 724 unit / 64 UI / 261 server; layout numbers in `RethinkLayout.swift`); **owner's next step: run build 11 on the phone and move things by eye.** Still open with the owner: answer 12 from the current screenshot; Instruments lane; then the Xcode upload. Build 9 was never uploaded; this round ships before item 13.
- **(was) NOW — build 9: Lane B ([ROADMAP item 18](issues/ROADMAP.md)) and Lane A ([item 19](issues/ROADMAP.md)) merged and pushed to `main` 2026-11-11 (`6deaab8`); TestFlight upload is the owner's next step, then sync the assigned build number; and two threads:** (a) **item 17, the depth & polish pass** — built on `owner-tweaks` 2026-11-03 → 11-05, reviewed, and **pushed to `main` 2026-11-10**; TestFlight upload next; shipped list, in-progress item, remaining order for build 8 and open owner calls: [handoff](issues/current/handoff-depth-pass.md); rulings and gate: [FIGMA.md §12](design/FIGMA.md). Still open from the build 7 review: the editor's review pills preview tomorrow under a "Today" label ([FIGMA.md §11](design/FIGMA.md)). (b) **finish the #6c/#6d acceptance boxes** ([checklist: push-client spec §6](issues/current/implement-spec-push-client.md), ROADMAP item 8) — remaining boxes are time-gated: digest 6–11 band, dedup silence, upgrade push, far-day, pruning, toggle-off re-verify under the never-erase code — plus the spec-14 dormancy box (not time-gated).
- **Also NOW — [ROADMAP item 19](issues/ROADMAP.md), the Lane A surface pass:** frames owner-approved 2026-11-11 ([FIGMA.md §14](design/FIGMA.md)); merged and pushed with item 18 (`6deaab8`, 2026-11-11); dark mode uses the owner's 2026-11-11 palette. Open: light disabled-label strength, dark city-picker check, and the Figma Color/Typography token writes (owner ruling pending).
- **NEXT (ship order — ROADMAP has the full table):** the ship phase's waves in order ([ship doc](issues/current/ship-phase.md)) → the owner's submission steps → App Store review. **After 1.0:** item 13 onboarding v2 build → the watched-session dad-test round (item 14) — both moved after 1.0 by owner ruling 2026-11-18. Item 10's live boxes are ticked except the non-204/429 UX ([spec §5](issues/current/implement-spec-beta-feedback.md)).
- **BLOCKED:** nothing hard-blocked. The 2026-08-22 external-path hold is **overridden** (owner ruling 2026-11-17 — straight to App Store review; [ROADMAP item 9](issues/ROADMAP.md)).

## 3. Standing flags (not blockers)

- **Known limitations (recorded, accepted):** DST *inside* a time-of-day window is untested (Asia/Dubai has no DST) — do not assert DST-correctness for windows. Half-hour zones (e.g. +05:30) render `ha`-style clock labels :30 off in both the iOS `RangeText`/`TimeDeriver` and the server `jobs/labels.js`.
- **Client mirrors:** the client deliberately re-implements slices of server logic — read [ADR-0007](adr/0007-client-side-mirrors.md) before touching threshold semantics on either side.
- **UI is Figma-first:** frames precede code — decision of record: [ADR-0008](adr/0008-figma-first-ui-gate.md); completed frame passes: [FIGMA.md §7–§8](design/FIGMA.md); the open onboarding-v2 pass: [FIGMA.md §9](design/FIGMA.md).
- **Deferred-with-conditions:** the list + promote conditions live in [ROADMAP §Deferred](issues/ROADMAP.md).

## 4. Built state

Per-item build status: [ROADMAP](issues/ROADMAP.md) (ship path + completed — the single home). Architecture as it exists: [CLAUDE.md](../CLAUDE.md).

*History: `git log`. (STATUS_LOG.md was deleted 2026-08-10 — git history keeps it.)*
