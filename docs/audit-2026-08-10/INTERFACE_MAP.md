# INTERFACE_MAP — specs as contracts, shared surfaces, and the conflict matrix

**Audit date:** 2026-08-10 · Phase 2 of the reconciliation audit (branch `reconcil`).
Method: every implementation plan read as a contract (owns / consumes / exposes /
mutates), not as implementation detail. Findings ranked by **future optionality
destroyed**, not by difficulty of fix.

---

## 1. The shared surfaces

| # | Surface | Where it lives | Who touches it |
|---|---|---|---|
| S1 | **`/rating` wire contract** (request + response) | ADR-0003/0004/0005, golden snapshot tests | Everything. Spec 14 freezes it; #6c/#6d consume it; #7/#8 widen the request side; WeatherKit must still satisfy its `timezone` field |
| S2 | **Evaluation semantics** (`evaluateHour`, `findLongestWindow`, night-stitch) | `src/decision/`, ADR-0003 amendments | Both push jobs consume; **spec 14 §3 mirrors it client-side**; #8 extends it (`requireTrue`) |
| S3 | **Xcode project container** (pbxproj, scheme, entitlements, `PRODUCT_BUNDLE_IDENTIFIER`) | `ios/TimeIt/TimeIt.xcodeproj` | WeatherKit track (holds ~20 uncommitted lines), push client (needs APNs entitlement), shippability (bundle-ID rename), every future iOS PR |
| S4 | **`AuthoredActivity` + `ActivityStore` semantics** | `ios/TimeIt/TimeIt/Models`, `Services` | Spec 14 redefines `window == nil` (whole-day → **dormant**) and adds `flexible`; #6c §9's snapshot projection reads it; WeatherKit track holds a (trivial) edit to the same file |
| S5 | **Device snapshot schema + shared `validateActivities`** | #6c spec, `src/routes/` | #6c/#6d consume; spec 14 changes what clients *send* (dormancy exclusion, ±1h-widened windows); #8's kind-validation would tighten it |
| S6 | **Metric catalog** (server truth + `StaticMetricCatalog` client mirror) | `src/weather/metricCatalog.js`, iOS mirror | #7 flips metrics live; #8 adds kind-awareness; the unwritten `GET /api/v1/metrics` ADR hangs over it |
| S7 | **Weather provider seam** (`fetch.js`/`index.js`/adapter + timezone sourcing) | `src/weather/` | WeatherKit handoff proposes a provider-descriptor refactor; #7 assumes the *current* adapter shape; the wire `timezone` (S1) depends on an IANA zone only Meteosource supplies in-band |
| S8 | **Figma token/page structure** | foundations doc, iteration handoff | The two docs contradict each other (see C6); spec 14 §9 requires a catch-up pass on the same pages |
| S9 | **The docs structure itself** | CLAUDE / CONTEXT / STATUS / ROADMAP / specs | Every track pays a manual reconciliation tax; state is quadruplicated (see DOCS_AUDIT) |

**The two load-bearing surfaces for the whole system:**

1. **S1, the wire contract** — it is the system's keystone and its discipline is genuinely
   good (golden snapshots, twin ADRs, additive-only hours). But its *frozen-ness* is now
   the force generating client-side mirrors (S2's `HourQuality` is the fourth), and no doc
   records that trade-off as a decision.
2. **S3, the Xcode project container** — the current chokepoint. One hand-written file,
   no ownership protocol beyond prose in OWNER_NOTES, currently serializing three tracks
   behind ~20 lines of uncommitted churn (see C1). Every path to shipping runs through it.

---

## 2. Contract extract per implementation plan

Compact form; full field extraction preserved in the audit transcript.

| Plan | Status (stated) | Owns exclusively | Consumes | Exposes | Mutates |
|---|---|---|---|---|---|
| **#6c registration + digest** | backend built/merged/deployed per STATUS — **but every acceptance box in the spec is still `[ ]` and §6 is still prescriptive** | `devices` schema, device routes, APNs seam, weather cache, digest job, **iOS §9 opt-in client (unbuilt)** | #6b, #5c, ADR-0001/2/5/6, engine, timeBoundary, **#6d's `bucket_date` helper (ordering inversion — #6d is declared downstream)** | snapshot shape, `getCachedWeather`, `sendPush`/`StaleTokenError`, `validateActivities`, cron slot | S1 (prod wiring → cache), S5 (defines), Postgres, S4 (re-upsert triggers), env |
| **#6d Perfect-window detector** | backend built/audited/merged/deployed per STATUS — same unchecked-boxes staleness | `notification_state` + bucket-date dedup, Perfect-only/buckets-0–1 policy, push payload `{activityId, bucketDate}` | #6c verbatim, engine `endIndex` exclusivity, ADR-0003/4/6 | `bucket_date` helper, payload contract (the only iOS-facing artifact; **no iOS work specced anywhere for handling it**) | Postgres, S5 (reads window), env (none new) |
| **#7 marine data** | ⚠️ STALE banner; blocked on tier investigation | marine wiring path, placeholder inventory | Meteosource paid tier (unconfirmed), adapter seam **as currently shaped** | live marine metrics in catalog | S6, S7, S1 (values only) — **body still edits deleted `src/activities/fishing.js`** |
| **#8 requireTrue + kind-validation** | ⚠️ STALE banner; scope grew 2026-07-15, body never updated | `requireTrue` branch; threshold-shape-vs-metric-kind validation | engine `checkThreshold`, `validateRatingRequest`, S6 | new threshold type on the request wire | S1 (request side), S2, S6 |
| **Spec 14 dashboard rework** | locked 2026-08-09, unbuilt, untracked in git & ROADMAP | dormancy model, gradient card, `HourQuality`, ±1h flex, phrases toggle, detail redesign, prefill table | S1 (frozen hard), `TimeDeriver`, fixture, **"the designed 4-step wizard" — which exists only as Figma frames** | dormancy-exclusion rule inherited by the future #6c §9 client | S4 (redefines `nil` window; adds `flexible`), S5 (what clients send), S2 (client mirror), S8 (§9 catch-up pass) |
| **WeatherKit handoff** | exploratory, "not a locked spec — no ADR" | provider-descriptor proposal, JWT auth design, IANA-gap analysis | S7 as-is | none yet (pre-decision) | would restructure S7, add env, move timezone-sourcing out of the adapter — **an ADR-scale decision currently living in a handoff** |
| **Figma iteration handoff** | 2026-07-31, live working doc for the Linux Figma agent | fileKey/node map, PUA codepoint table, Figma workflow rules | foundations doc, #5c spec | approval-gate protocol | S8 — and declares `Theme colors` "superseded, slated for cleanup" |
| **Figma foundations spec** | ✅ IMPLEMENTED banner **contradicted by six unticked §8 boxes** | design-system structure, palette, token collections | grill, Guidelines.md | tokens the iteration work binds to | S8 — declares `Theme colors` "code-truth reference, stay untouched" |
| **design-decisions-issue-5** | both child specs built; doc still in `current/`, pervasive stale future tense | nav model, card anatomy, SF Symbols manifest | ADRs, Guidelines.md | seed Template rows, symbol tables | none (reference doc) |

**Ghost plans** (work items with no spec, discovered only in passing mentions):
TestFlight distribution (nowhere in ROADMAP — the project has no ship step), the
analytics events table (grill Q5 locked "at launch", dropped), the range-first wizard
build (ROADMAP: "spec deliberately unwritten"), temp-driven header + dark-mode adoption
(Figma foundations §7), the AQ adapter (grill Q4 "pre-launch"; `cli-iqair.js` sits in the
repo root), Railway Hobby upgrade, seed-threshold finalization, `GET /api/v1/metrics` ADR.

---

## 3. Conflict matrix — ranked by optionality destroyed

| # | Conflict | Surfaces | What it destroys | Severity |
|---|---|---|---|---|
| **C1** | **The phantom pbxproj lock.** STATUS/ROADMAP/OWNER_NOTES serialize the push client, the bundle-ID rename, and (by contention on `AuthoredActivity.swift`) spec 14 behind "the WeatherKit agent's in-flight track" — which on disk is ~20 lines of Xcode churn, no branch, no stash, and a handoff that self-describes as pre-spec | S3, S4 | **All iOS optionality.** Nothing on the ship path can move until a 5-minute owner decision (commit or discard) is made. The block is documentation, not code | **Critical** |
| **C2** | **Spec 14's `HourQuality` reverses ADR-0002 without an ADR.** "Client-side engine … duplicates the crown-jewel Window logic, two engines drift" was an explicit rejection; spec 14 §3 builds exactly that mirror (fourth mirror overall, after StaticMetricCatalog, TimeDeriver/labels.js) | S2, S1 | Locks the client to re-implementing every future threshold-semantics change (e.g. #8's `requireTrue`) in two places forever; forecloses the alternative (server-returned per-hour tiers) without ever weighing it | **High** |
| **C3** | **Spec 14 assumes an unbuilt, unspecced wizard.** §6 is written against "the designed 4-step wizard"; code has only the #5b `AddActivityView`→`ActivityEditorView` flow; ROADMAP still says the wizard spec is "deliberately unwritten until the #6 wave completes" — and doesn't know spec 14 exists | S4, ROADMAP | An executing agent must invent the wizard or silently reinterpret onto the editor — either way, un-reviewed scope. Also: two authoritative docs now disagree about what the next UX step even is | **High** |
| **C4** | **#7 and WeatherKit mutate the same seam with incompatible shapes.** #7 targets the current adapter contract; the WeatherKit handoff restructures that contract into provider descriptors and moves timezone-sourcing out of the adapter. Whichever builds first silently invalidates the other's spec | S7 | Provider-seam optionality; also the IANA-resolution decision (lat/lon→zone dependency) is architecture being decided in a handoff, not an ADR | **High** |
| **C5** | **#7/#8 bodies still edit the deleted curated-activity architecture.** Both banners disown their own bodies; #8's grown scope (kind-validation — a real silent-false-Perfect hole) appears only in the banner, nowhere in the body | S1, S2, S6 | An agent executing either spec as-written resurrects `src/activities/*` semantics (`-pro`/`-lite` ids, server-owned thresholds) — the exact architecture Phase 2 deleted | **Medium** (banners mitigate) |
| **C6** | **The two Figma docs give opposite orders about the same tokens.** Foundations: "`Theme colors` … stay untouched — code-truth reference"; iteration handoff: "Legacy — do NOT use: `App Colors`, `Theme colors` (superseded, slated for cleanup)". Foundations header also claims §8 acceptance passes over six unticked boxes | S8 | Any design-track agent must guess which doc wins; spec 14 §9 sends the next agent straight into this contradiction | **Medium** |
| **C7** | **Spec 14's flex-widening vs push copy honesty.** The ±1h toggle *sends* the widened window (snapshot included), so digest/detector copy ("Perfect 7–10am") can name shoulder hours the user never picked — while §4's own copy promises "we'll also *watch* … your window" (mental model: window unchanged). Wire-consistent, user-model-inconsistent | S5 | Small now; becomes un-fixable copy debt once push copy and card sublabel are pinned "word-for-word" to each other | **Low–Medium** |
| **C8** | **The frozen grill still presents superseded contracts as locked.** `bestDayIndex` (rejected in ADR-0004), fixed-168 count, `floor(index/24)` day rule, UTC-index windows, day-0-strict digest — all un-bannered in the "Decisions locked" table; ADR-0003's digest text likewise never annotated after ADR-0006 superseded it | S9 | Re-litigation risk: an agent loading the grill as decision-of-record rebuilds rejected designs. Pure docs debt, cheap to fix | **Low** (but recurring) |
| **C9** | **#6c⇄#6d dependency inversion.** #6c ("required by #6d") consumes #6d's `bucket_date` helper; harmless now (both built) but the specs teach the wrong build order to any future reader | S9 | Trivial | **Low** |

---

## 4. What is *not* contaminated (worth saying)

- The wire contract itself (S1) is internally consistent across all six ADRs and both
  built push jobs — the twin-ADR + golden-snapshot discipline worked.
- Spec 14's server-side scope fence ("zero diffs") is genuinely honored by its own text —
  its contamination is all client-side and doc-side.
- The push backends' seams (APNs, cache, db) are cleanly factored and no plan disputes
  their ownership.

---

## Appendix A — Phase 0 flat inventory

*(name · purpose · stated status · last git commit; UNTRACKED = never committed — see
PRIORITY_RESET and DOCS_AUDIT for what to do with each)*

Completed and remaining files are inventoried in DOCS_AUDIT.md §1 (file-by-file, with
line counts); the audit-relevant subset:

| File | Purpose | Stated status | Last commit |
|---|---|---|---|
| docs/CONTEXT.md | domain glossary | current | 2026-08-03 |
| docs/STATUS.md | orientation hub | current (banner 2026-08-03) | 2026-08-03 |
| docs/STATUS_LOG.md | session history | "stale by design, do not read" | 2026-07-20 |
| docs/issues/ROADMAP.md | build order | current — **does not know spec 14 exists** | 2026-08-03 |
| docs/adr/0001–0006 | decisions of record | accepted; 0003 carries stale digest text | 2026-06-17→07-20 |
| docs/personalization_grill.md | frozen rationale record | closed 2026-06-17; 4 superseded rows un-bannered | 2026-07-03 |
| docs/design/figma_foundations…md | design-system spec | "✅ IMPLEMENTED" over unticked §8 | 2026-07-19 |
| issues/current/design-decisions-issue-5.md | #5 UX reference | children completed; doc stale-tensed | 2026-07-20 |
| issues/current/handoff-figma-design-iteration.md | Figma-agent working doc | live | 2026-08-01 |
| issues/current/handoff-weatherkit-provider-abstraction.md | provider exploration | "not a locked spec — no ADR" | **UNTRACKED** |
| issues/current/implement-spec-issue-6c…md | push backend + iOS client spec | backend live; boxes unchecked; §9 unbuilt | 2026-08-03 |
| issues/current/implement-spec-issue-6d…md | detector spec | backend live; boxes unchecked | 2026-08-03 |
| issues/current/implement-spec-issue-7…md | marine data | ⚠️ STALE banner | 2026-07-19 |
| issues/current/implement-spec-issue-8…md | requireTrue | ⚠️ STALE banner; scope grew, body didn't | 2026-07-19 |
| issues/current/implementation-spec-14…md | dashboard rework | locked 2026-08-09, unbuilt | **UNTRACKED** |
| issues/completed/ (9 files) | archives | done | 2026-05-22→08-03 |
| docs/review/ (2 files) | resolved review records | done | 2026-06-24 / 07-15 |
| docs/OWNER_NOTES.local.md | private operational facts | current | UNTRACKED (by design) |
| CLAUDE.md · README.md · ios/GLOSSARY.md · ios/README.md · ios/guidelines/Guidelines.md | orientation / iOS reference | current | various |
