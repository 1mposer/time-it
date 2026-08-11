# PRIORITY_RESET — one ranked list, four buckets, one provable use case

> **Folded into [`docs/issues/ROADMAP.md`](../issues/ROADMAP.md) 2026-08-10** — the ROADMAP is the living copy; this file is the archived rationale.
>
> ⚠️ **Amended 2026-08-11 ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)):** the "Figma design-iteration track" deferral's rationale ("design exploration must not gate code") is reversed — frames now precede UI code. Everything else stands.

**Audit date:** 2026-08-10 · Phase 3 of the reconciliation audit (branch `reconcil`).
**Gate passed 2026-08-10 — owner answers folded in below** (spec 14 promoted to SHIP;
WeatherKit working tree to be discarded, track deferred post-ship; Meteosource renewal
confirmed "soon").
Objective function: **ship with one provable use case as fast as possible, so the
feedback loop starts.** Anything not shortening that path is deferred or deleted.

---

## The provable use case

A real user (the owner plus one to three recruits) installs time-it from TestFlight,
authors **one Activity with their own hours at their real location**, and over the
following week the dashboard truthfully answers *"is it worth going out during my
hours?"* against live weather — and when a Perfect window appears inside ~48h, the phone
tells them unprompted. The proof event: **at least one user acts on a rating or push and
reports whether reality matched.** The riskiest assumption this loop tests first is
**value** — that being told "your hours are good" actually changes when someone goes
out — ahead of any polish or breadth assumption. Everything in SHIP is on this path.

**Owner amendment (2026-08-10):** "truthfully" is raised to spec 14's standard — the
dashboard must answer for *the user's own hours* with the per-hour gradient, and the
detail page must lose its per-hour-numbers redundancy, **before** the first cohort sees
it. This adds the spec 14 minimal cut (SPEC_14_FEASIBILITY.md) to the path.

**TestFlight ≠ the Xcode cable install.** The build the owner has run on their own
iPhone is an Xcode development install — it proves the app works, and it is not a
distribution channel. TestFlight (App Store Connect → archive upload → invite link) is
how *recruits* install without a cable, how builds update over the air, and what flips
the backend to the production APNs host (`NODE_ENV=production`, per OWNER_NOTES). The
use case needs recruits, so it needs TestFlight.

---

## SHIP — required for the provable use case (in execution order)

| # | Item | Justification (one sentence) |
|---|---|---|
| 1 | **Discard the pbxproj working tree** (owner decision 2026-08-10; the `DEVELOPMENT_TEAM` line regenerates the next time Xcode signing is configured) | The "in-flight WeatherKit track" blocking all iOS work was a phantom — ~20 lines of Xcode churn with no branch, no stash, no spec (INTERFACE_MAP C1); every doc note enforcing the lock dies with it. |
| 2 | **Renew Meteosource** (#11, owner — confirmed "soon") | Every live path 502s until this happens; the product is dead in production today. |
| 3 | **Railway Hobby upgrade** (owner) | The trial credit (~$4.85/16 days as of 08-03) dies mid-loop otherwise, taking the deployed backend and both push jobs with it. |
| 4 | **Bundle-ID rename → `com.timeit.app.dev`** (Debug + Release; unblocked by #1) | The app is unshippable under `com.timeit.app` — another Apple account owns it. |
| 5 | **Spec 14 — minimal cut** (owner-promoted into ship scope 2026-08-10; exact cut and prerequisites in SPEC_14_FEASIBILITY.md) | The owner has declared glance-trust and the de-redundant detail page part of the shippable product, and building it **before** the push client means the snapshot projection is written once, against the final dormancy model. |
| 6 | **iOS push opt-in client** (the #6c §9 remainder + handling #6d's `{activityId, bucketDate}` payload; extract into its own small spec, see MERGE) | The deployed push backends are dead weight without it, and "the phone tells them unprompted" is the thesis's differentiator. |
| 7 | **#6c/#6d live acceptance pass** (spec §4s; needs 2 + 6) | The push loop has never been proven end-to-end against production. |
| 8 | **TestFlight distribution** (new item — App Store Connect setup, archive/upload, `NODE_ENV=production`) | This is the ship step, and no document in the repo had ever named it. |

Sequencing: 1–4 are parallel owner-actions totaling well under a day; 5 and 6 are the
remaining engineering, in that order — a preference, not an essential dependency (the
§9 snapshot projection is a small adapter, so 6 may overlap or swap with 5 if spec 14
stalls); 2 gates 7; everything gates 8.

## DEFER — real value, wrong now (with promote conditions)

| Item | Why deferred | Promote when |
|---|---|---|
| **Docs consolidation** (DOCS_AUDIT.md) | Off the user path — but it removes a recurring per-session tax and is ~one session of mostly deletions | Immediately — it can run parallel to SHIP 1–4 |
| **Spec 14 full scope beyond the cut** — the 4-step wizard build, ±1h flexibility | The wizard exists only in Figma (C3) and flex carries push-copy semantics debt (C7); neither is needed for glance-trust | With the post-ship design wave; wizard needs its own spec first |
| **WeatherKit provider abstraction** (owner-confirmed post-ship 2026-08-10) | Exploratory, no ADR, genuine IANA-zone blocker, conflicts with #7 on the same seam (C4) | Post-ship, or Meteosource cost/reliability bites; write the ADR first |
| **#8 requireTrue + threshold-kind validation** | The kind-validation hole is unreachable from the shipped client; the spec body predates the rebuild and must be rewritten before execution — and once spec 14's `HourQuality` mirror exists, any threshold-semantics change lands in **two** places (note added there) | An astronomy data source lands, or a non-mirrored client can author |
| **`GET /api/v1/metrics` route + ADR, `RemoteMetricCatalog`, error-`code` enum, stale-activity reconciliation** (one bundle) | All four exist to absorb a metric-catalog change no live plan will cause | The first metric flip (#7-class event) is scheduled |
| **Analytics events table** (grill Q5, locked "at launch", then dropped) | TestFlight feedback + conversation suffices for a ≤5-user cohort | Cohort grows past ~5 users |
| **Seed-threshold finalization** (owner pass over `SeedTemplates.swift`) | Provisional numbers are fine for a cohort authoring its own hours; spec 14's prefills partially subsume this | Ride along with the spec 14 build |
| **Dark mode + temp-driven header** (Figma foundations §7 leftovers) | Pure visual wave, zero thesis risk | Post-ship design wave |
| **Air-Quality adapter** (grill Q4; `cli-iqair.js` experiment) | Data breadth does not shorten the path to the loop | A user persona demands it |
| **Pro/StoreKit + paywall · cloud sync** | Monetization and sync before a single user is inverted order | Post-loop, per #5b §8's existing deferral |
| **Figma design-iteration track** | Design exploration must not gate code; spec 14's cut builds data-first and lets rendering track approved frames | Folds into spec 14's §9 pass |

## KILL — bloat, redundancy, or solutions to problems this project doesn't have

| Item | Justification |
|---|---|
| **The WeatherKit file-lock standing order** ("do not touch, in-flight track") | Owner-confirmed dead 2026-08-10 — discard the working tree, delete every "in-flight track" note in STATUS/OWNER_NOTES/handoffs; the handoff doc survives (banner: deferred post-ship) as the future ADR's input. |
| **#7 marine spec as written** | Pre-rebuild STALE: edits deleted `src/activities/fishing.js`, uses abolished `-pro`/`-lite` ids, hinges on UAE-specific sources under a worldwide posture — recreate as a fresh one-pager only when a validated fishing persona exists (GitHub issue stays as tombstone). |
| **STATUS_LOG.md** | A file whose own header forbids reading it should not exist; git history already is the append-only log. |
| **Grill Q4's "pre-launch AQ + Marine" requirement** | Data breadth as a launch precondition contradicts the objective function; the grill stays as rationale, this requirement is dead. |
| **The `app.js` startup-log cosmetic** (OWNER_NOTES item 4) | Fold into the next backend commit; delete the note. |
| *(already dead, stays dead)* #6a accounts/auth | CUT per ADR-0001 — noted only so the list is total. |

## MERGE — duplicates; survivor named

| Duplicates | Survivor |
|---|---|
| ROADMAP's "UX evolution (post-#6d)" entry ⟷ spec 14 (same work, two records; ROADMAP unaware spec 14 exists) | **Spec 14** (ROADMAP entry becomes a pointer) |
| #6c spec §9 + #6d live-acceptance remainder ⟷ the two mostly-completed backend specs they're trapped inside (the ff9a712/45e8a0b move-then-revert confusion is this exact ambiguity) | **A new small "iOS push client + live acceptance" spec**; the backend specs move to `completed/` with ticked boxes |
| design-decisions-issue-5.md (stale-tensed, children completed) ⟷ Guidelines.md | **Guidelines.md** absorbs the SF-Symbols manifest + card anatomy; the rest archives to `completed/` |
| Figma foundations spec ⟷ Figma iteration handoff (contradict each other on `Theme colors`/`App Colors`, C6) | **One consolidated Figma-truth doc** (DOCS_AUDIT) |

## Redundancy called out explicitly

- **Status is quadruplicated:** STATUS banner ⟷ ROADMAP ⟷ per-spec headers ⟷ CLAUDE.md
  build-order — four places to update per event, demonstrably diverged (unchecked
  acceptance boxes under "deployed" banners).
- **The push-path contract is stated four times:** CLAUDE.md §push, ADR-0006, the #6c/#6d
  specs, STATUS §5.
- **Visual truth is split three ways with contradictions:** Guidelines.md (carries cut
  tab-bar/sign-in/PRO rows it disclaims), design-decisions-issue-5.md, the two Figma docs.
- **Glossary content overlaps three files:** CONTEXT.md ⟷ README.md language section ⟷
  ios/GLOSSARY.md.

---

## Gate record (2026-08-10)

| Q | Owner answer | Effect |
|---|---|---|
| WeatherKit track liveness | Not critical; discard | SHIP #1 becomes *discard*; track → DEFER post-ship; lock notes → KILL |
| Spec 14 as ship-gate | Yes — ship with spec 14 (gradient trust + detail de-redundancy) | Spec 14 minimal cut → SHIP #5, ahead of the push client |
| Money/ops | Meteosource renewal "soon"; WeatherKit post-ship | SHIP #2 confirmed; WeatherKit stays DEFER |
| TestFlight | Owner has run the Xcode device build successfully | Confirms the app works end-to-end on device; TestFlight itself (recruit distribution) remains unbuilt — SHIP #8 stands |
