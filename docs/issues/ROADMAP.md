# Roadmap — the single home for per-item status

> Reset 2026-08-22 (owner-gated; the grill record + tester evidence: [`docs/research/onboarding-tester-evidence-2026-08.md`](../research/onboarding-tester-evidence-2026-08.md)). Predecessor: the [2026-08 ship-loop roadmap](completed/roadmap-2026-08-ship-loop.md) (archived; its open items 8, 9, 10 carry forward below with their original numbers — item numbers are unique across both roadmaps).
>
> **Objective — pass the dad test:** a new user reaches a real verdict about their own hobby in **under two minutes, unassisted**, and opens the app again the next day (evidence + measurement method: the research note above). This is the prerequisite for the carried finish line, unchanged and still unfinished from the predecessor: **a TestFlight user acts on a push and reports whether reality matched.**

## Ship path (in order; item 8 runs in parallel throughout)

| # | Item | Owner | Status |
|---|---|---|---|
| 8 | #6c/#6d live acceptance (carried; checklist: [push-client spec §6](current/implement-spec-push-client.md)) | both | **in progress — parallel lane.** Production lane proven 2026-08-22 (record: [archived roadmap](completed/roadmap-2026-08-ship-loop.md)). Remaining boxes are time-gated: digest 6–11 band, dedup silence, Good→Perfect upgrade, far-day, pruning, toggle-off re-verify |
| 11 | **Mobbin reference curation** — owner picks reference onboarding flows (e.g. Duolingo) via the connected Mobbin MCP and hands them to the design pass | owner | todo — feeds item 12; the MCP connection itself is done (2026-08-22) |
| 12 | **Onboarding v2 — design** ([FIGMA.md §9](../design/FIGMA.md) is the pass stub) — a **new dedicated Figma page**, frames built **fresh** (§7/§8 and the existing Screens pages are never edited); flow: hobby pick (Templates as starting points) → **three one-tap personalization questions**, prefilled from the template — (1) "When do you usually [run]?" → sets the mandatory **Range** (the activity is born ranged and non-dormant — locked contract), (2)+(3) two comfort questions → the hobby's two most important thresholds — plus an optional **fine-tune offer** with an always-visible back-out (fine-tune's destination is a decision *inside this design pass*, not a promise of the old wizard screens) → **location ask** (one plain sentence of why; refusal falls into the city picker — the refusal path is a **first-class frame**) → **live verdict reveal** → one optional "Add another?" → dashboard. **Vocabulary rule:** "range" and "threshold" never appear on these screens — plain language only; strings live in Figma (design truth), never in docs | owner + agent | todo — gated on item 11's references; owner approval of frames per [ADR-0008](../adr/0008-figma-first-ui-gate.md) closes it |
| 13 | **Onboarding v2 — build** (TDD against the approved §9 frames; server contract untouched; produces a ranged, non-dormant Activity; ships to the internal TestFlight group) | agent | Figma-gated ([ADR-0008](../adr/0008-figma-first-ui-gate.md)) on item 12 |
| 14 | **Watched-session dad-test round** — fresh install per tester, owner watches (in person or video call), says nothing, times to first verdict, notes hesitations; next-day return checked by asking; observations appended to the [research note](../research/onboarding-tester-evidence-2026-08.md) as the pass/fail evidence (no analytics — that stays deferred) | owner | after item 13 |
| 9 | **TestFlight external path** (carried) — privacy-policy URL ([ADR-0010](../adr/0010-data-retention-privacy-posture.md) is the source sheet) → Test Information → external group → Beta App Review → public link → App Privacy answers (owner-ops guide: [handoff](current/handoff-testflight-owner-ops.md)); release-submission still carries the BetaGate gate-off/relocate + `AppTransaction` migration ([beta spec §3](current/implement-spec-beta-feedback.md)) | owner | **HELD (owner ruling 2026-08-22, grill Q8): every external step waits until onboarding v2 ships (item 13)** — today's no-onboarding first-run burns first impressions on strangers; internal testers (known, reachable) are unaffected. Internal testing live since 2026-08-22 (record: [archived roadmap](completed/roadmap-2026-08-ship-loop.md)) |
| 10 | **Beta feedback** (carried) — [spec](current/implement-spec-beta-feedback.md) | both | built + live-accepted except **one box: live non-204/429 UX** ([spec §5](current/implement-spec-beta-feedback.md)); the gate-off/relocate step rides item 9's release submission. Build record: [archived roadmap](completed/roadmap-2026-08-ship-loop.md) |

## Deferred (with promote conditions)

| Item | Promote when |
|---|---|
| **Plain-language rework of the shipped "range" surfaces** (spec-14 card's "Nothing in your range" phrase, the range chip, the editor's Range section) — fresh frames in the onboarding-v2 style on the new page; old frames untouched; sweeps the [CONTEXT.md](../CONTEXT.md) Range/Threshold _Avoid_ notes' shipped-exception when done | onboarding v2 is validated by the watched-session round (item 14) |
| **Scratch-wizard power-user path** (the old 5-screen wizard's unbuilt screens 2–5 — demoted to a power-user path, grill 2026-08-22) **+ the owner's expectation that the Add-sheet wizard is deprecated** in favor of onboarding-style authoring (expectation, not a locked kill) | onboarding v2 wins with testers and the fine-tune destination (item 12's decision) needs a deeper edit surface |
| ±1h flexibility (spec 14 full-scope leftover) | post-onboarding design wave |
| WeatherKit provider abstraction ([analysis](completed/handoff-weatherkit-provider-abstraction.md)) | post-ship, or Meteosource cost/reliability bites — write the provider-descriptor ADR first |
| #8 `requireTrue` + threshold-kind validation ([stub](deferred/implement-spec-issue-8-require-true-threshold.md)) | an astronomy source lands, or a non-mirrored client can author |
| `GET /api/v1/metrics` route + its ADR · `RemoteMetricCatalog` conformer · ADR-0005 error-`code` enum · client stale-activity reconciliation | the first metric flip (#7-class event) is scheduled |
| Analytics events table (personalization grill Q5, 2026-07 — not the 2026-08 grill) | cohort grows past ~5 users |
| Seed-threshold finalization (`SeedTemplates.swift` — owner pass) | rides the onboarding v2 build (item 13) — the three prefilled questions read these defaults |
| Dark-mode adoption + temp-driven header (Figma foundations §7 leftovers) | post-onboarding design wave |
| Air-Quality adapter (`cli-iqair.js` experiment) | a user persona demands it |
| Marine data (#7 — [GitHub](https://github.com/1mposer/time-it/issues/7); the stale spec was deleted 2026-08-10) | a validated fishing persona exists |
| Pro/StoreKit + paywall · iCloud sync | post-loop (per #5b spec §8). **Tripwire for the Pro build:** wire the StoreKit entitlement-change handler into `DeviceRegistration`'s re-upsert triggers — the server has no tier check ([ADR-0001](../adr/0001-no-accounts-guest-first.md)/[ADR-0006](../adr/0006-device-keyed-push-evaluation.md)), so a downgraded device's stale Pro snapshot keeps receiving Pro-level pushes until the client re-upserts (flagged 2026-08-17) |
| Surprise notification (out-of-range Perfect alert — the whole-day-discovery descendant; definition: [`ios/GLOSSARY.md`](../../ios/GLOSSARY.md)) | post-ship, when a validated user asks for out-of-range alerts |
| Devices-route abuse ceiling (rate limit in the feedback route's mold) — unauthenticated `PUT` has no growth cap and, under [ADR-0010](../adr/0010-data-retention-privacy-posture.md) never-erase, no code path shrinks the `devices` table (adversarial audit of `63ed332`, 2026-08-22) | the public TestFlight link goes live (item 9 unfreezes), or any abnormal `devices` growth appears |

## Killed (stays killed)

- **#6a accounts/auth** — CUT ([ADR-0001](../adr/0001-no-accounts-guest-first.md)).
- **The grill Q4 "pre-launch AQ + Marine" requirement** — killed 2026-08-10; data breadth is not a launch precondition.
- **STATUS_LOG.md** and the **#7 spec-as-written** — deleted 2026-08-10 (git history keeps both).

## Completed

Ship-loop items 1–7 (+ the built halves of 8–10): see the [archived 2026-08 ship-loop roadmap](completed/roadmap-2026-08-ship-loop.md) — the record of that reset. Earlier: #1 · #3 · #4 · #10 · rebuild Phases 1+2 · #5a · #5b · #5c · #6b · #6c backend · #6d backend — specs + resolved handoffs live in [`completed/`](completed/), each bannered as a historical record.

## Rules

- The tree is the source of truth (the #5/#6 GitHub issues were removed; #7/#8/#11 remain on GitHub).
- A spec moves to `completed/` — boxes ticked, one-line banner added — in the **same commit** that merges its build; completed bodies are never edited again.
- `current/` holds only living work orders; handoffs carry a fold-in-by date at creation. **`deferred/`** holds stubs/specs for Deferred-table items (each linked from its row) — not living work, not historical record.
- **UI is Figma-first** — frames precede code ([ADR-0008](../adr/0008-figma-first-ui-gate.md), the decision of record).
- **Design lens (owner ruling, grill Q7 2026-08-22):** every screen is designed for the non-technical, technophobic user — the persona is a *chosen lens* ("designing around the outlier makes a good product for everyone"), not an evidence claim; the evidence itself lives in the [research note](../research/onboarding-tester-evidence-2026-08.md).
