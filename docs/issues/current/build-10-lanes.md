# Build 10 — lane plan (owner-ruled 2026-11-11)

> Living work order for the build-10 round. Status home: [ROADMAP item 20](../ROADMAP.md). Owner rulings of 2026-11-11 are inlined below; the lane briefs are the spawn contracts. **Build 9 was never uploaded — superseded by build 10** (same as build 8). Onboarding v2 (item 13) follows this round.

Purpose: the owner's four raw requests, turned into independent agent-assignable buckets. Orchestrator-written; not a spec; no fixes proposed. v1 was critiqued by a blind Opus 5.5 reviewer (12 findings); v2 accepts 11 and records the one it rejects.

## Baseline (verified today)
- `main` = `939582d`, build 9 merged + pushed 2026-11-11, **not yet uploaded** to TestFlight. Everything below is build-10+ work.
- ROADMAP §Deferred already assigns three build-8 review deferrals to **build 10**: (5) passed hours grey only on re-render, (8) `DashboardViewModel.timeDeriver` cache-per-forecast, (9) stale `programmaticSlot` haptic.
- iOS keeps **no client cache** (`DashboardViewModel.swift:210`); it POSTs `/rating` on launch, foreground return (`DashboardView.swift:207`), pull-to-refresh, and any activity change. The **server** memoises Meteosource 60 min per 2-dp lat/lon — Meteosource is not hit per client call; the Railway round-trip is.
- ADR-0007/0002: Window search, night-stitch, bucketing are **server-only**; the only live client mirror is per-hour `HourQuality`. A client cannot rate a new activity locally.
- Opening sequence: converge 1.3 s → hold 0.48 → rise 0.8 → beat 0.6 → welcome 1.2 → reveal (~4.5 s cold launch).
- FIGMA.md §12 (owner, 2026-10-06): **"no long press — a plain tap on the card opens the detail."** Request 2 reverses this.
- The fresh-eyes run was on **build 8** (`owner-tweaks 899566a`) with a fake weather server. Build 9 since shipped the five-step wizard ("Show only" retired, Review reveals the real card), the dark palette, the Converge opening — notes 9–12, 30, 34 may be stale.
- `npm audit`: 7 (1 critical, 2 high, 4 moderate); every fix is non-major, no `--force` needed.
- GitHub `1mposer/time-it` is **public**; secret scanning, push protection, Dependabot updates all **disabled**. 15 open issues; no triage labels exist. `/mattpocock-skills:triage` is not loaded in this session (the skill exists on disk in the mattpocock marketplace).
- No rate limit on `/rating`; ROADMAP §Deferred holds a devices-route rate-limit row gated on the public TestFlight link.

## Overlap routing (fresh-eyes notes → owning bucket)
| Notes | Owner | Why |
|---|---|---|
| 24, 31, 38 (delete depth, no long-press/reorder, no undo) | **B1** | request 2 asks for exactly this |
| 33 (lone metric card) | **B1** | two-metric minimum |
| 36 whole header/card geometry at large text | **B2** | same view as the hero edits; splitting geometry/scaling is not independent |
| 37 (no "updated" hint) | **D** | freshness is the cache's output |
| 16, 32, 34, 3/8, 4, 21 (plain bugs, no frame needed) | **A-fix** | |
| 1, 2, 5, 9–15, 17–20, 23, 25–30, 35 | **A-spec** | copy/visual, owner-ruled, Figma-first |

## Dispatch order
0. ~~Upload build 9~~ — owner ruling 2026-11-11: not uploaded; build 10 ships from the merged lanes. The first iOS lane to commit bumps `CURRENT_PROJECT_VERSION` to 10. A Release **archive** (no upload) runs once at the end of the loop as the ship check.
1. **Now, parallel, no shared files:** A0 (re-run), C1–C2, D.
2. **After D lands** (it owns cache invalidation rules that B1's delete/reorder must respect): B1, then B2 (B2 is gated on Q1).
3. **After A0 + owner rulings:** A-fix, A-spec.
4. **After A/B/D have ROADMAP rows:** C3 issue triage (so overlapping issues get rows, not "orphaned" labels).
5. **Later (owner's word):** C4 rate limit, its own bucket.
Every bucket's done-when includes the ROADMAP row + STATUS line (+ FIGMA.md gate state where a ruling changes) in the same commit — CLAUDE.md status-change rule.

---

## Lane RERUN (was A0) — Re-run the blind fresh-eyes test on build 9 against the real backend
**Done 2026-11-11 (`6a13e15`, merged):** [ADDENDUM-build9.md](../../research/fresh-eyes-2026-11-11/ADDENDUM-build9.md) — Release build against production; 31 STILL-TRUE, 3 FIXED-BY-BUILD-9 (#12 #30 #32), 3 FIXTURE-ARTEFACT (#21 #22 #31), 1 NOT-REACHED (#34). Top three live faults: #18/#19 ("Perfect" on a mostly-red day reproduces with real data — e.g. 1 of 5 hours green shows "20 · Perfect"), #1–3/#8/#13 (location-denied first run), #6/#27 (notifications switch ignores taps). **New server-side finding for FIXES/owner:** from ~day 5 the provider stops sending `uv_index`; the adapter's `uv_index ?? 0` turns absent data into `uV: 0` at noon, which passes any `max` threshold — a false-Perfect path (the `?? 0` default is only correct at night). Side effects: one simulator test device row written to the production `devices` table (its token will fail APNs and be blanked by the never-erase path); a second simulator "RERUN 17 Pro" was created and left in place.
Agent: one Opus agent, computer-use on the simulator (same harness as the first run), Release config or a local server with `DATABASE_URL`. Output: an addendum to `NOTES.md` marking each of the 38 notes still-true / fixed-by-build-9 / fixture-artefact. No code. Prerequisite for A-fix and A-spec.

## Lane FIXES (was A-fix) — Plain bugs from the tester record (iOS code, TDD, no frame)
Agent: one Opus implementer in a worktree; Sonnet verifier runs suites. Items (if A0 confirms them): 16 dot tap opens today not that day; 32 edge swipe-back dead on the detail; 34 dark-switch re-renders the overnight hour strip wrongly; 3/8 Settings says "Using current location" after denial and silently discards a chosen city; 4 city search returns one result; 21 lowercase moon label. Hardware check for 32 and the notifications switch (27).

## Lane SPEC (was A-spec) — State maps + owner page for the copy/visual faults
Agent: one Opus agent (judgement), Figma MCP connected (check `/mcp` first). Deliverable per request §6: `implement-spec-fresh-eyes-ux.md` (six state maps from §4, per-fault transition, copy-only vs frame, standalone vs item 13) + one owner artifact page (screenshot, one-line ask, a/b/c slot, priority). Cross-references the routed notes above instead of re-speccing them. No engine change (ADR-0011).

## Lane MANAGE (was B1) — Activity management (iOS interaction)
**Item 0 — build-10 purge:** on first launch of build 10, delete all locally stored activities (and any per-card state keyed on them); if the device is opted in to push, upsert an empty `[]` snapshot so the server goes dormant for it. Guarded by a stored build marker so it runs once. Unit test: a store seeded with activities is empty after the migration; the devices client receives one empty PUT.
Agent: one Opus implementer, `phone-gestures` skill; Sonnet verifier. Items: delete from the activity detail page; long-press on a dashboard card → context menu Delete / View details / Move (reorder, persisted in `ActivityStore`); two-metric minimum on the wizard Metrics step with a hint; "add metric" tile with the metric square's exact geometry in the detail grid, opening the wizard on Metrics. Must record the long-press supersession of the 2026-10-06 ruling in FIGMA.md §12. Must honour D's rule: reorder never refetches; delete drops the activity from the cache without a refetch. Absorbs build-10 deferrals (5) and (9).
- [x] **Done 2026-11-11 (lane branch, not merged):** items 0–5 landed, one commit each — build-10 purge (`activityPurge.build10` marker, collapsed-card ids cleared, one empty `putSnapshot` for an opted-in device, stamped-not-purged under the UI-test mock); two-metric Metrics gate + "Pick at least two"; long-press context menu (View details / Move ▸ Up·Down / Delete, confirmed; `ActivityStore.move`, no POST); detail Delete; add-metric tile (detail grid, metric-square geometry, opens Metrics); deferral (5) detail-hero minute tick and (9) single-use scroll marker. FIGMA.md §12 records the long-press supersession. Not done: deferral (5)'s dashboard-card half (outside this lane's DashboardView scope). Unit 596 → 614, UI 48 → 51 green.

## Lane POLISH (was B2) — Visual tune (iOS, mini-edits lane — owner ruled 2026-11-11)
Agent: one Opus implementer; Sonnet verifier screenshots every surface in both appearances. Items: hero's three numerals grow to fill the dead space above the first card; first card moves down to eye level; "Add Activity" text removed, "+" enlarged into the freed space; detail-page **container backgrounds** (each card/container's fill, not the page ground — the page ground stays the dashboard's) darker and calmer green (`Theme.swift` token, both modes); opening sequence — hold the first solid-colour frame 1 s longer and pre-warm the converge so it plays clean (profile alongside; cold launch becomes ~5.5 s). Note 36 header geometry at large text sizes. Reviewer point accepted: the hold ships regardless of whether the lag reproduces on hardware.
- [x] **Done 2026-11-12 (lane branch, not merged; owner rules from simulator screenshots):** items 1–8, one commit each — header meta readings 13 → 17pt; the first Activity card rests at eye level (the first-launch capsule's line, `DashboardLayout`); the add slot is one enlarged "+" (limit copy and first-launch hero unchanged); detail containers take `surface/detail-container` (page ground untouched); a 1.0 s first-frame hold before the converge (the mount hitch moves out of the springs; the remaining ~117 ms simulator windows appear in every variant — on-device Instruments check still owed); note 36 — header words cap at xxxLarge (≈26% of the screen at AX-XXXL, was ≈53%); card strips grey on a minute tick (deferral 5, card half); the add-metric tile's press state without a `Button`. Unit 614 → 624, UI 51 → 54 green on a dedicated "POLISH 17 Pro" simulator.

## Lane LOCKDOWN (was C1–C2) — GitHub security + dependency fix (now, Sonnet)
**Done 2026-11-11 (`2075c5d`, merged to main):** secret scanning, push protection, Dependabot alerts + security updates all enabled (read back). `npm audit fix` cleared 5 of 7 (1 critical, 2 high, 2 moderate); the 2 left are dev-only `nodemon`→`minimatch` (needs a breaking nodemon downgrade — not done). **Dependabot after rescan:** one open alert (#13, `minimatch` medium, dev-only via nodemon) — the same leftover; the undici/qs alerts GitHub printed on the first push were the pre-fix lockfile and closed on rescan.
Enable secret scanning, push protection, Dependabot alerts + security updates (`gh api -X PATCH` or owner in Settings → Code security; record which). One `npm audit fix` (no `--force`), `npm test` green. Nothing touches git history.

## Lane TRIAGE (was C3) — Issue triage (after the new ROADMAP rows exist, Sonnet, by hand to four states)
Sort all 15 open issues into done / parked / orphaned / superseded; create the four labels; label or close each with the AI-triage disclaimer. Overlaps to route rather than orphan: #19 → A, #31 → B1, #23 → D, #17 → A-fix (note 4), #18 → item 13. Then write the rule into ROADMAP §Rules: *an open issue must have a ROADMAP row or a triage label; a triage-labelled issue untouched for two months is stale* — reconciled with the existing "tree is the source of truth" rule.

## Lane THROTTLE (was C4) — Rate limit on `POST /api/v1/rating` (later)
In the feedback route's mold, with tests. The deferred devices-route row keeps its own promote condition (stays deferred).

## Lane CACHE (was D) — Client-side forecast cache (iOS view-model/networking, TDD)
Agent: one Opus implementer in a worktree; Sonnet verifier. Constraints: cache the last `ForecastResponse` on disk keyed by 2-dp lat/lon, anchored on `forecastStart`; serve from cache on launch, foreground return and dashboard re-entry while fresh; TTL **3 h** (owner, 2026-11-11) with the data's age shown ("Updated 10:43", closes note 37); pull-to-refresh bypasses; offline shows the cached forecast with its age. **Activity add/edit:** POST only the changed activity and merge into the cached response when `forecastStart`/`timezone` match, else full refetch — never rate locally (ADR-0002/0007). Owns the invalidation rules B1 must respect. Absorbs build-10 deferral (8). Changes the `scenePhase` refetch at `DashboardView.swift:207` — the one file shared with B2; D lands first.
- [x] **Done 2026-11-11 (lane branch, not merged):** rules 1–5 landed test-first — `Services/ForecastCache.swift` (2-dp key, TTL 3 h from the fetch instant + stale at the location's local midnight past `forecastStart`, disk in Caches, memory-only under XCTest / UI-test mock), cache-aware `loadForecast()` (single-Activity POST + merge on matching `forecastStart`/`timezone`, else full refetch; delete/reorder/dormancy replay locally with no POST — MANAGE mutates `ActivityStore` or calls `reconcileForecastWithStore()`), `refresh()` bypasses, "Updated H:mm" label, a transient failure keeps the cached forecast, one `TimeDeriver` per forecast (deferral 8). Unit 564 → 596, UI 48 green at HEAD (the pull-to-refresh baseline is now 1 launch fetch). ROADMAP/STATUS rows land with the assembling merge.

## Rejected reviewer point
Bump `CURRENT_PROJECT_VERSION` in the assembling merge, not in B. CLAUDE.md's rule is that any commit intended for the next TestFlight build bumps it in the same commit; the first iOS bucket to land does so, later ones find it already at 10. The real prerequisite is step 0 above.

## Owner answers 2026-11-11
1. POLISH runs in the mini-edits lane (code → simulator screenshots → owner rules). No frames.
2. Long-press reversal confirmed — MANAGE records the supersession in FIGMA.md §12.
3. **Resolved by a bigger ruling:** build 10 wipes every existing activity on first launch (one-time purge, the item-15 legacy-seed purge is the mold) — every install, owner and TestFlight testers alike, starts empty on this build. No grandfathering question remains. Consequence for the push path: the purge must also PUT an empty `[]` snapshot for an opted-in device so the server stops digesting/alerting on the wiped activities (server rows are never deleted — ADR-0010 — the snapshot just goes dormant). Lives in MANAGE as its first item.
4. Green = each container's background fill on the detail page; the page ground stays identical to the dashboard's.
5. All request-2 observations and the animation lag were seen on build 9.
6. Cache TTL = 3 h.
7. ~5.5 s cold launch accepted.
8. **This round ships first, then onboarding v2 (item 13).** Reason given: the whole app's look has changed. STATUS/ROADMAP ship order updates in the first lane's status commit.

## Open questions for the owner (original list, kept for the record)
1. B2 is visual: Figma frames first (ADR-0008) or the 2026-11-05 "mini edits" lane (code → simulator screenshots → you rule)?
2. The long-press menu reverses your 2026-10-06 "no long press" ruling. Confirm the reversal.
3. Two-metric minimum: what happens when an existing single-metric activity is edited — block Save until a second is added, or grandfather it?
4. Detail page "green container": which one — the score-ring hero band, the metric cards, or the day picker?
5. Were requests 2's observations made on build 9 (post-11-11 merge) or build 8? Same for the lag.
6. Cache TTL: "as long as reasonably possible" — 3 h? 6 h? Until `forecastStart` is a day old? (Age always shown.)
7. Cold launch grows from ~4.5 s to ~5.5 s with the extra 1 s hold. Acceptable?
8. Where does item 13 (onboarding v2, next in ship order) sit relative to this round? B1's wizard rule and A-spec faults 2/4 sit inside it.

## Token posture (owner, 2026-11-11: effective, not throttled, but no million-token bursts)
- **Waves, not a fan-out.** At most three implementer agents live at once. Wave 1: RERUN + LOCKDOWN + CACHE. Wave 2: MANAGE, then POLISH. Wave 3: FIXES + SPEC (after RERUN). Wave 4: TRIAGE. THROTTLE later.
- **Model by lane:** Sonnet for LOCKDOWN, TRIAGE, THROTTLE and every verifier; Opus for the five iOS/spec lanes. No verifier for docs-only lanes.
- **Every brief carries a stop rule:** the lane's done-when, the files it may touch, and "report and stop if the suite is red twice or the task exceeds its scope" — the brief is the budget.
- **Expensive surfaces are single-shot:** RERUN's computer-use session and SPEC's Figma session run once each, with a written deliverable, never re-driven for a second look.
- Reference magnitude: the Opus critique in this session cost ~100k tokens in under two minutes. An implementer lane with a verifier runs several times that. Nine lanes over days is the expected spend; nine lanes in one hour is the burst to avoid.
