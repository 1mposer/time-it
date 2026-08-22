# Roadmap — 2026-08 ship loop (ARCHIVED)

> 📦 **Archived 2026-08-22 — historical record; never edited again.** This was the 2026-08-10 ship-loop reset (items 1–10). Its open items (8, 9, 10) carry forward, with their numbers, into the [successor roadmap](../ROADMAP.md); the grill that produced the successor is recorded in the [onboarding tester-evidence research note](../../research/onboarding-tester-evidence-2026-08.md). Relative links below are as written at archive time (from `docs/issues/`) and may not resolve from this folder.

> Reset 2026-08-10 (owner-gated; rationale: [`docs/audit/AI_audit/PRIORITY_RESET.md`](../audit/AI_audit/PRIORITY_RESET.md)). Objective: **ship one provable use case so the feedback loop starts** — a TestFlight user authors one Activity with their own hours at their real location; the dashboard answers truthfully for those hours; a Perfect window inside ~48h pushes unprompted; at least one user acts on it and reports whether reality matched.

## Ship path (in order)

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | Discard the WeatherKit working tree; dissolve the pbxproj lock | agent | ✅ done 2026-08-10 |
| 2 | Renew Meteosource ([#11](https://github.com/1mposer/time-it/issues/11)) — everything live 502s until then | owner | ✅ done 2026-08-11 — renewed on the **Standard** plan; endpoint switched `/flexi/`→`/standard/` same day |
| 3 | Railway **Hobby** upgrade before the trial credit dies | owner | ✅ done 2026-08-11 |
| 4 | Bundle-ID rename → `com.timeit.app.dev` (Debug + Release, Xcode UI) — unshippable until done | owner | ✅ done — recorded 2026-08-19 (one owner Xcode pass: rename in Debug+Release **plus** the `aps-environment: development` entitlement; release build installed on a real device) |
| 5 | **Spec 14 Figma catch-up pass** — frames built + owner-approved ([FIGMA.md §7](../design/FIGMA.md), incl. the push client's opt-in surfaces) | owner + agent | ✅ done — frames built 2026-08-13 + post-audit wrap-up fixes same day (inventory: FIGMA.md §7 — card gradient/no-rating-word/all-red, detail §7 skeleton incl. nocturnal variant, Settings phrases + Notifications, true-empty + push-callout frames, I3 strings block); **owner-approved 2026-08-14** — [ADR-0008](../adr/0008-figma-first-ui-gate.md) gate open: 6's rendering + 7's opt-in UI unblocked |
| 6 | **Spec 14 minimal cut** — [spec](completed/implementation-spec-14-dashboard-rework.md) (cut + ambiguity resolutions: [feasibility audit](../audit/AI_audit/SPEC_14_FEASIBILITY.md)) | agent | ✅ **done 2026-08-14** — logic layer built 2026-08-12, amended 2026-08-13 (showcase = full four-template catalog, owner ruling from the Figma Empty—Showcase frame — spec §1 amendment; dormancy + POST exclusion, `HourQuality` mirror + fixture invariant, gradient stops, phrase reduction, prefills + template-prefill recovery, dismissals + delete-all re-seed, dismiss-ledger guard; flag-decoder asymmetry recorded in ADR-0007), logic final-audited (191 unit + 19 UI green); **rendering built 2026-08-14, TDD, against the owner-approved frames** ([FIGMA.md §7](../design/FIGMA.md)) — §2 gradient card (range chip, best-stretch sublabel, all-red day, showcase + true-empty states, live/dormant interleave), §5 Settings phrases row + Differentiate-Without-Color lock, §7 detail skeleton (window header / setup-once / range-zoomed week / tap-to-expand, nocturnal 6-row parity), §1 editor retrofit (window toggle deleted — every save confirms a range); 217 unit + 25 UI tests green; spec moved to `completed/` with the rendering merge. **Awaiting owner review (flagged, not decided): I2** all-dormant header hides its weather rows (proposal) · **I3** provisional phrase strings (`TrajectoryPhrase.swift` = card sheet `92:9`) |
| 7 | **iOS push opt-in client** — [spec](current/implement-spec-push-client.md) | agent | ✅ **done 2026-08-17** — built TDD against the approved frames: §1 Settings Notifications toggle (location-first enable flow through the #5c doors — system prompt when not-yet-asked, else the city picker; denied prompt reverts the switch) + the one-time dashboard callout (Figma `266:5`, deep-links to Settings, ✕ persists); §2 `DeviceRegistration` (Keychain install UUID via rename-proof service string, full-snapshot upsert with dormant exclusion + nocturnal passthrough, home-else-GPS — never the last-resolved cache, re-upsert triggers incl. empty-snapshot on last-delete and 24h launch-if-stale, DELETE on opt-out with launch retry); §3 push-tap routing (`perfectWindow` → dashboard with the named card scrolled into view — card links switched to value-based navigation for the pop; digest → dashboard). 270 unit + 30 UI green; server untouched (172) |
| 8 | #6c/#6d live acceptance (checklist: [push-client spec §6](current/implement-spec-push-client.md)) | both | **in progress — production lane proven 2026-08-22**: first Perfect-window push delivered end-to-end (TestFlight build, `NODE_ENV=production`, [ADR-0010](../adr/0010-data-retention-privacy-posture.md) never-erase deploy). The 2026-08-19 sandbox round root-caused the silent stale-token row-wipe → ADR-0010 redesign (audited + deployed 2026-08-22). Remaining boxes: digest 6–11 band, dedup silence, Good→Perfect upgrade, far-day, pruning, toggle-off re-verify |
| 9 | **TestFlight distribution** — App Store Connect, archive/upload, `NODE_ENV=production` on Railway for the production APNs host | owner | **internal testing live 2026-08-22** — ASC app "Time it - Activity Weather" (`com.timeit.app.dev`), build 1.0 (1) uploaded 2026-08-19, 3 internal invites incl. the owner (owner's phone now runs the TestFlight build); `NODE_ENV=production` flipped 2026-08-22. Remaining (external path — delegated: [handoff](current/handoff-testflight-owner-ops.md)): privacy-policy URL (source: ADR-0010, host outside this repo) → Test Information → external group → Beta App Review → public link → App Privacy answers. Release-submission still carries the BetaGate gate-off/relocate + `AppTransaction` migration ([beta spec §3](current/implement-spec-beta-feedback.md)) |
| 10 | **Beta feedback + test-build disclaimer** — [spec](current/implement-spec-beta-feedback.md); ships **inside** item 9's first build | both | server route ✅ done 2026-08-18 (`POST /api/v1/feedback` + `suggestions` table, 181 server tests green); Figma frames **owner-approved 2026-08-19** ([FIGMA.md §8](../design/FIGMA.md) — round-2 hand-edit is the code reference); **iOS client ✅ built 2026-08-19** against the §8 round-2 frames — `BetaGate` sandbox-receipt runtime gate (spec §3, pinned both ways), disclaimer banner + compact suggestion pill (26pt visual / 44pt tap target per the §8 code-sweep note) on every dashboard state's scroll stack (owner ruling), suggestion sheet (non-204 keeps the typed text with Send as the retry, 429 throttle copy, 1000-char counter mirror), `FeedbackClient` POST keyed on the shared Keychain install UUID; 282 unit + 34 UI green, server untouched (181). **Live acceptance 2026-08-22:** banner + pill render on the TestFlight build and a real-device suggestion landed as a `suggestions` row ([spec §5](current/implement-spec-beta-feedback.md) — one box left: live non-204/429 UX). Remaining: the item-9 gate-off/relocate release step |

## Deferred (with promote conditions)

| Item | Promote when |
|---|---|
| Spec 14 full scope: the 5-screen wizard's unbuilt screens 2–5 (Name+Icon → Range → Metrics → Review — needs its own spec; screen 1, the Add sheet, is shipped) + ±1h flexibility | post-ship design wave |
| WeatherKit provider abstraction ([analysis](completed/handoff-weatherkit-provider-abstraction.md)) | post-ship, or Meteosource cost/reliability bites — write the provider-descriptor ADR first |
| #8 `requireTrue` + threshold-kind validation ([stub](current/implement-spec-issue-8-require-true-threshold.md)) | an astronomy source lands, or a non-mirrored client can author |
| `GET /api/v1/metrics` route + its ADR · `RemoteMetricCatalog` conformer · ADR-0005 error-`code` enum · client stale-activity reconciliation | the first metric flip (#7-class event) is scheduled |
| Analytics events table (grill Q5) | cohort grows past ~5 users |
| Seed-threshold finalization (`SeedTemplates.swift` — owner pass) | ride the spec 14 build |
| Dark-mode adoption + temp-driven header (Figma foundations §7 leftovers) | post-ship design wave |
| Air-Quality adapter (`cli-iqair.js` experiment) | a user persona demands it |
| Marine data (#7 — [GitHub](https://github.com/1mposer/time-it/issues/7); the stale spec was deleted 2026-08-10) | a validated fishing persona exists |
| Pro/StoreKit + paywall · iCloud sync | post-loop (per #5b spec §8). **Tripwire for the Pro build:** wire the StoreKit entitlement-change handler into `DeviceRegistration`'s re-upsert triggers — the server has no tier check ([ADR-0001](../adr/0001-no-accounts-guest-first.md)/[ADR-0006](../adr/0006-device-keyed-push-evaluation.md)), so a downgraded device's stale Pro snapshot keeps receiving Pro-level pushes until the client re-upserts (flagged 2026-08-17) |
| Surprise notification (out-of-range Perfect alert — the whole-day-discovery descendant; definition: [`ios/GLOSSARY.md`](../../ios/GLOSSARY.md)) | post-ship, when a validated user asks for out-of-range alerts |
| Devices-route abuse ceiling (rate limit in the feedback route's mold) — unauthenticated `PUT` has no growth cap and, under [ADR-0010](../adr/0010-data-retention-privacy-posture.md) never-erase, no code path shrinks the `devices` table (adversarial audit of `63ed332`, 2026-08-22) | the public TestFlight link goes live, or any abnormal `devices` growth appears |

## Killed (stays killed)

- **#6a accounts/auth** — CUT ([ADR-0001](../adr/0001-no-accounts-guest-first.md)).
- **The grill Q4 "pre-launch AQ + Marine" requirement** — killed 2026-08-10; data breadth is not a launch precondition.
- **STATUS_LOG.md** and the **#7 spec-as-written** — deleted 2026-08-10 (git history keeps both).

## Completed

#1 · #3 · #4 · #10 · rebuild Phases 1+2 · #5a · #5b · #5c · #6b · #6c backend · #6d backend — specs + resolved handoffs live in [`completed/`](completed/), each bannered as a historical record. The shared #5 visual/UX reference was absorbed into [`ios/guidelines/Guidelines.md`](../../ios/guidelines/Guidelines.md) 2026-08-10.

## Rules

- The tree is the source of truth (the #5/#6 GitHub issues were removed; #7/#8/#11 remain on GitHub).
- A spec moves to `completed/` — boxes ticked, one-line banner added — in the **same commit** that merges its build; completed bodies are never edited again.
- `current/` holds only living work orders; handoffs carry a fold-in-by date at creation.
- **UI is Figma-first** — frames precede code ([ADR-0008](../adr/0008-figma-first-ui-gate.md), the decision of record).
