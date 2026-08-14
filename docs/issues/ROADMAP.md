# Roadmap — the single home for per-item status

> Reset 2026-08-10 (owner-gated; rationale: [`docs/audit/AI_audit/PRIORITY_RESET.md`](../audit/AI_audit/PRIORITY_RESET.md)). Objective: **ship one provable use case so the feedback loop starts** — a TestFlight user authors one Activity with their own hours at their real location; the dashboard answers truthfully for those hours; a Perfect window inside ~48h pushes unprompted; at least one user acts on it and reports whether reality matched.

## Ship path (in order)

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | Discard the WeatherKit working tree; dissolve the pbxproj lock | agent | ✅ done 2026-08-10 |
| 2 | Renew Meteosource ([#11](https://github.com/1mposer/time-it/issues/11)) — everything live 502s until then | owner | ✅ done 2026-08-11 — renewed on the **Standard** plan; endpoint switched `/flexi/`→`/standard/` same day |
| 3 | Railway **Hobby** upgrade before the trial credit dies | owner | ✅ done 2026-08-11 |
| 4 | Bundle-ID rename → `com.timeit.app.dev` (Debug + Release, Xcode UI) — unshippable until done | owner | pending |
| 5 | **Spec 14 Figma catch-up pass** — frames built + owner-approved ([FIGMA.md §7](../design/FIGMA.md), incl. the push client's opt-in surfaces) | owner + agent | ✅ done — frames built 2026-08-13 + post-audit wrap-up fixes same day (inventory: FIGMA.md §7 — card gradient/no-rating-word/all-red, detail §7 skeleton incl. nocturnal variant, Settings phrases + Notifications, true-empty + push-callout frames, I3 strings block); **owner-approved 2026-08-14** — [ADR-0008](../adr/0008-figma-first-ui-gate.md) gate open: 6's rendering + 7's opt-in UI unblocked |
| 6 | **Spec 14 minimal cut** — [spec](current/implementation-spec-14-dashboard-rework.md) (cut + ambiguity resolutions: [feasibility audit](../audit/AI_audit/SPEC_14_FEASIBILITY.md)) | agent | logic layer ✅ built 2026-08-12, amended 2026-08-13 (showcase = full four-template catalog, owner ruling from the Figma Empty—Showcase frame — spec §1 amendment) (dormancy + POST exclusion, `HourQuality` mirror + fixture invariant, gradient stops, phrase reduction, prefills, dismissals + delete-all re-seed — unit + UI suites green; provisional phrase strings await owner review, spec I3); audit follow-ups landed 2026-08-13, TDD (template-prefill recovery for dormant showcase cards — `SeedTemplates.prefill(for:)`, stargazing no longer drafts diurnal; dismiss-ledger guard; flag-decoder asymmetry recorded in ADR-0007); logic final-audited (191 unit + 19 UI green); **rendering (spec §2/§5/§7) is the live work** — unblocked 2026-08-14 (frames approved); the spec in `current/` is the work order and moves to `completed/` with the rendering merge |
| 7 | **iOS push opt-in client** — [spec](current/implement-spec-push-client.md) (owner-side prerequisite: the APNs entitlement in Xcode) | agent | unbuilt — after/alongside 6's rendering; opt-in UI unblocked 2026-08-14 (frames approved) |
| 8 | #6c/#6d live acceptance (checklist inside the push-client spec) | both | blocked on 7 |
| 9 | **TestFlight distribution** — App Store Connect, archive/upload, `NODE_ENV=production` on Railway for the production APNs host | owner | new — the ship step |

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
| Pro/StoreKit + paywall · iCloud sync | post-loop (per #5b spec §8) |
| Surprise notification (out-of-range Perfect alert — the whole-day-discovery descendant; definition: [`ios/GLOSSARY.md`](../../ios/GLOSSARY.md)) | post-ship, when a validated user asks for out-of-range alerts |

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
