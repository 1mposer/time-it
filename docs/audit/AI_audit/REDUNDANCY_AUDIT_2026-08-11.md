# Redundancy audit — restated facts across living docs

**Date:** 2026-08-11
**Position in history:** run **after** the priority reset + docs consolidation of 2026-08-10 ([`PRIORITY_RESET.md`](PRIORITY_RESET.md)) and **after** the last commit, `405bbba` — *"fix: switch Meteosource to the Standard-plan endpoint + refresh its docs"* (the flexi→standard switch). Branch: `ideating`.
**Status:** **adjudicated 2026-08-12** — rulings, corrections, and applied edits: [`RESOLUTION_2026-08-12.md`](RESOLUTION_2026-08-12.md); policy outcome: [ADR-0009](../../adr/0009-tiered-doc-truth.md). This file is review evidence, not project documentation — it proposes no truth and makes no edits.

## Method & scope

Two parallel read-only sub-agents (server-docs pass; docs↔iOS pass), findings merged and deduped by a coordinating agent, which independently spot-verified every finding marked *(verified)* against file contents at `405bbba`.

- **Definition of a finding:** a concrete fact stated *in full* in ≥2 living docs (or in one wrong file), where one file should own it and the rest should link. Links/pointers and mere term *usage* are not findings; re-*definitions* are.
- **In scope (living docs):** root `CLAUDE.md`, root `README.md`, `docs/CONTEXT.md`, `docs/STATUS.md`, `docs/issues/ROADMAP.md`, `docs/issues/current/*`, `docs/API_documentation/meteosource/README.md`, `docs/design/FIGMA.md`, `docs/OWNER_NOTES.local.md`, `docs/personalization_grill.md`, `ios/GLOSSARY.md`, `ios/README.md`, `ios/guidelines/Guidelines.md`.
- **Excluded by design (frozen history — restatement there is fine):** `docs/adr/*`, `docs/issues/completed/*`, `docs/audit/*`, `docs/review/*`.

**Totals: ~45 unique restated facts; 11 already drifted (copies disagree as of this audit).**

---

## A. Live drift — copies that disagree right now

| # | Fact | The disagreement |
|---|---|---|
| A1 | Showcase card | `ios/GLOSSARY.md:20` "**not an Activity** … never saved to the store" vs `implementation-spec-14-dashboard-rework.md:39,49` — the same card **is** a stored dormant Activity (`window == nil`, "stored, visible, never evaluated"). Direct contradiction about store membership. *(verified)* |
| A2 | First-launch store state | `ios/GLOSSARY.md:17` "the store starts empty" vs `spec 14:53–54` "First launch seeds the two template cards dormant". *(verified)* |
| A3 | Wizard size | `ios/GLOSSARY.md:39` "**5 logical screens**" vs `spec 14:5,133` + `ROADMAP.md:23` "4-step wizard". Two canonical numbers in circulation. *(verified)* |
| A4 | Wizard/showcase status tag | `ios/GLOSSARY.md` tags wizard/showcase entries "(planned)"; after the 2026-08-10 minimal-cut they are post-ship "(deferred)" per ROADMAP + the spec 14 header. GLOSSARY predates the decision and was not reconciled. |
| A5 | Leftover flexi ① | `docs/OWNER_NOTES.local.md:58` still says "Meteosource **flexi** subscription lapsed … Owner: renew" (listed as Not-done item 1) — renewed on **Standard** 2026-08-11 per ROADMAP:10 / STATUS:3. *(verified)* |
| A6 | Leftover flexi ② | `docs/personalization_grill.md:43` cold-start handoff says "Meteosource base DONE (`flexi` ~164 clean hourly)" — plan is now `standard`, live-verified 166 (~161–168) per `meteosource/README.md:17`. *(verified)* |
| A7 | Stray vendor export | Untracked `docs/API_documentation/meteosource_standard_openapi.json` duplicates `docs/API_documentation/meteosource/openapi.json` — a second physical copy at the wrong level, violating the one-directory-per-adapter rule stated in CLAUDE.md. |
| A8 | Railway plan status | `docs/OWNER_NOTES.local.md:60–61` frames the Hobby upgrade as future ("eventually") — done 2026-08-11 per ROADMAP:11 / STATUS:3. |
| A9 | Setup env vars | `README.md:44–46` setup says add `API_KEY` only — `CLAUDE.md:345` says `DATABASE_URL` is mandatory since #6c (`initDb()` failure exits non-zero). Following README's setup verbatim fails. *(verified)* |
| A10 | Digest send time | `docs/CONTEXT.md:67` "sent at the Device's local **6am**" vs `CLAUDE.md:212` + push spec — the built behavior is the **6–11 catch-up band** ("not `=== 6`"). *(verified)* |
| A11 | Figma file name | `ios/README.md:8` "Main - Time-it" vs `docs/design/FIGMA.md:5` "Main - Time it". Trivial (hyphenation); fileKey matches. |

---

## B. Not yet drifted — restated facts, grouped by proposed owner

### B1. Vendor facts → owner: `docs/API_documentation/meteosource/README.md`

These are exactly why commit `405bbba` (flexi→standard) was a multi-file edit.

1. Endpoint path `/api/v1/standard/point` + "path segment is subscription-scoped" — also in full in `CLAUDE.md:232` (and echoed in CLAUDE.md's test description ~line 323).
2. `/free/` tier caps at 24h — `CLAUDE.md:232` + vendor README:17.
3. `timezone=auto` is the only mode exposing the IANA zone, and returns *local* wall-time timestamps — `CLAUDE.md:230,235` + vendor README:9.
4. `uv_index` is `null` at night; adapter defaults `?? 0`; fixed the 2026-07-12 decode bug — stated in **three** places: `CLAUDE.md:178`, `CLAUDE.md:235`, vendor README:18.
5. `wind.speed`/`precipitation.total`/`cloud_cover.total` can be individually absent per hour → adapter maps to `null` — `CLAUDE.md:180,235` + vendor README:19.
6. Upstream refresh cadence (10 min–1 h, owner-confirmed; basis of the 60-min cache TTL) — vendor README:25; `CLAUDE.md:244`'s parenthetical restates the cadence rather than only linking.
7. **Reverse violation:** vendor README:19 carries the *engine* rule "`checkThreshold` fails on `null`/`undefined`" — engine behavior does not belong in a vendor doc.

### B2. Status facts → owner: `docs/issues/ROADMAP.md`

1. "Push backends built/deployed; iOS opt-in client unbuilt" — stated in **7 files**: STATUS:38, `CLAUDE.md:13`, README:16,38, CONTEXT:5 (with hardcoded merge/deploy dates), push spec:3, OWNER_NOTES:76. Worst offender in the audit.
2. The Standard-renewal + Hobby-upgrade event (with dates) — ROADMAP:10–11 + STATUS:3 + STATUS:26, even though `STATUS.md:3` itself declares "nothing here restates it". *(verified — the restatement is in the same sentence as the claim)*
3. TestFlight needs `NODE_ENV=production` (sandbox APNs host while unset) — 5 files: `CLAUDE.md:250`, push spec:7, STATUS:26, ROADMAP:17, OWNER_NOTES:73–75.
4. `com.timeit.app` belongs to another Apple account; `.dev` is the permanent bundle ID; Xcode rename pending — 5 files: OWNER_NOTES:14–33,43–44, `CLAUDE.md:250`, ROADMAP:12, STATUS:25, push spec:4.
5. WeatherKit track discarded + deferred post-ship (2026-08-10) — STATUS:24, ROADMAP:9,24, OWNER_NOTES:63–64.
6. APNs entitlement in Xcode is the owner-side push prerequisite — push spec:4, ROADMAP:15, OWNER_NOTES:76–77.
7. Pro tier deferred / not enforced — README:24, ROADMAP:32.
8. Single-replica always-on requirement (2+ replicas duplicate pushes) — `CLAUDE.md:200,253`, STATUS:37, OWNER_NOTES:54.
9. **Charter violations:** STATUS §4 "Built state" (37–39) restates ROADMAP per-item status despite STATUS's own "a fact stated in two homes is a bug" (STATUS:20); `CLAUDE.md` declares it "carries no per-issue status" (~355) yet its intro (line 13) is a status claim.
10. iOS build status (#5a–c shipped/audited/live-verified; Dubai fallback deleted by #5c) — ios/README:3 + STATUS:38 + CONTEXT:57.

### B3. Wire/engine contract → owner: root `CLAUDE.md`

1. Window semantics (integers 0..23, location-local, half-open, absent = whole day, wrap = nocturnal, `startHour === endHour` rejected) — near word-for-word in `CLAUDE.md:105` and `CONTEXT.md:42`.
2. `days[]` dense/contiguous, per-activity length, never assume 7; diurnal 7–8, nocturnal one shorter — `CLAUDE.md:169` + CONTEXT:34,45 + `ios/guidelines/Guidelines.md:121` (which also carries the null-day-never-rolls-forward rule with CONTEXT:122).
3. `startIndex`/`endIndex` are **global** indices into `hours[]`, rendered in response `timezone` — CLAUDE.md days bullet + Guidelines:120.
4. Nullable trio `windSpeed`/`rainFall`/`cloudCover` (renders "—") — CLAUDE.md hours bullet + Guidelines:122.
5. 168 is a ceiling; count is provider-determined; never fabricate — **7 spots**: CLAUDE.md:13,164,176,233 + CONTEXT:74,80,89 + README:55.
6. ~50 activities ceiling is a DoS guard, not a tier gate — CLAUDE.md:100,226 + CONTEXT:94.
7. Unknown/coming-soon metric = hard 400 (false-Perfect guard) — CLAUDE.md ~96,188,226,283 + CONTEXT:48,100 + Guidelines:183 (six-metric list also enumerated there — any adapter landing makes the iOS copy stale).
8. Placeholder table (darkness 0, douglasScale 0, seaWarning false, tide 0 + blocked-on sources) — CLAUDE.md:288–300 (table) re-spelled per-entry in CONTEXT:100,104,107.
9. Device upsert contract (PUT path, `{ apnsToken, home, activities }`, last-write-wins, empty-`[]` valid, 204) — CLAUDE.md:202–208,224 + CONTEXT:64 + push spec:20,23 + README:56.
10. `DELETE /devices/:id` idempotent 204 — CLAUDE.md + README:57 + push spec:15.
11. Detector contract (first Perfect per (device, activity, bucket), buckets 0–1, Perfect-only, bucket-date dedup never index) — CLAUDE.md:216 + CONTEXT:70 + README:16.
12. Digest content rules (one/device/day, only-when-qualifying, week-ahead buckets 2..end) — CLAUDE.md:212 + CONTEXT:67 + push spec:47.
13. Detector payload `{ type: 'perfectWindow', activityId, bucketDate }` — verbatim in CLAUDE.md:216 + push spec:27.
14. `Z`-suffix-for-Swift's-`ISO8601DateFormatter` rationale — same sentence in CLAUDE.md:57 + CONTEXT:77.
15. Response `timezone` = location zone; client renders from `forecastStart`+`timezone`+`index` — CLAUDE.md:55–57,165–167 + CONTEXT:77,83.
16. APNs env-var set (`APNS_KEY` PEM content, `APNS_KEY_ID`, `APNS_TEAM_ID`, optional `APNS_TOPIC`; lazy build) — CLAUDE.md:250,345 + OWNER_NOTES:44,48.
17. Half-hour-zone `ha`-label limitation (labels.js + iOS TimeDeriver) — CLAUDE.md:256 + STATUS:30.
18. Absent-data B2 rule (`null`/`undefined` fails threshold) — CLAUDE.md:241 + CONTEXT:89 + spec 14:92–93 + vendor README:19 (see B1.7).

### B4. Domain terms → owner: `docs/CONTEXT.md`

1. Threshold semantics (required-fail ⇒ Bad; non-required-fail ⇒ Good-not-Perfect; flag `forbidTrue`) — CONTEXT:16–31 + CLAUDE.md:104,280–281 + spec 14:90–94. Spec 14 also renames "non-required" → "optional" — vocabulary slip, not semantic.
2. Night-stitch mechanics (evening-keyed, morning tail belongs to the evening, orphan morning dropped) — CONTEXT:45 + CLAUDE.md:169,~173,~239.
3. Wrapped From>To range is the one and only nocturnal signal — CONTEXT:42 + `ios/GLOSSARY.md:79`.
4. Diurnal = per calendar day; nocturnal = per night (evening + next morning as one unit) — CONTEXT:34,44–45 + GLOSSARY:81–85.
5. Mandatory-Range is a client-UI rule only (server keeps accepting window-less); ranges whole-hour — CONTEXT:38 + GLOSSARY:69–70,54 (GLOSSARY declares CONTEXT owns Range, then restates).
6. Show-but-don't-judge (thresholds ⊆ displayMetrics gap) — CONTEXT:97 + CLAUDE.md thresholds bullet + GLOSSARY:57.
7. Pursuit authored as one-or-more Activities (Variant affordance) — CONTEXT:10,111 + GLOSSARY:88.
8. Caller-supplied activities / engine holds no list / curated list = client Templates — CLAUDE.md:13,45,77 + CONTEXT:13,112 + README:22 — full re-explanations each time.
9. Device identity = Keychain install UUID (survives reinstall) + APNs token — CONTEXT:61 + CLAUDE.md:200 + push spec:19.
10. README:7–9,15 re-*defines* Range/rating vocabulary instead of glossing + linking.
11. **Status-tracking gap:** the deferred "surprise notification" is fully defined only in GLOSSARY:113–117 (CONTEXT:39 holds the discard); it is absent from ROADMAP's deferred table (the declared status home).
12. Discarded whole-day-discovery model → surprise-notification descendant — GLOSSARY:113–117 + CONTEXT:39.

### B5. Design truth → owner: `docs/design/FIGMA.md`

1. Header temp-band table (Default <20/20–32/≥33; UAE ≤33/34–37/>37) — byte-duplicated in GLOSSARY:92–96 and FIGMA.md:59 (GLOSSARY already links §4, then restates the whole table).
2. 9-wizard-frame inventory (Add 1 · Name+Icon 1 · Range 3 · Metrics 2 · Review 2) — GLOSSARY:104 + FIGMA.md:7,45.
3. Full light-mode palette + chip tier colors + ocean-blue gradient — byte-duplicated across `Guidelines.md:12–42` and FIGMA.md:59–63; only one can be authoritative (STATUS's truth table says Figma; `Theme.swift` tests pin Guidelines).
4. Activity-card geometry (radius 16, pad 14/12, ~365w, gaps 8–10) — Guidelines:77–81 + FIGMA.md:72.
5. Design-system contents description — ios/README:8 + FIGMA.md:7. (Internal inconsistency noted: FIGMA.md says "8 component sheets" while its own §2 lists 9.)
6. ADR-0008 gate scope (rendering/opt-in UI gated on approved frames; non-visual layer not gated) — re-explained in full in **5 living files**: spec 14:7–9,191–194, FIGMA.md:76,82, STATUS:26,32, ROADMAP:13–15,49, push spec:6. Living statement belongs in FIGMA.md §6; decision of record is ADR-0008 (frozen).
7. Spec-14 catch-up frame list — near-verbatim full copies in spec 14 §9 (183–189) *and* FIGMA.md §7 (82); the list will change during the pass.
8. Figma fileKey `t3ZRvcYPnSRPKElSLAFqmG` — FIGMA.md:5 + spec 14:31 + ios/README:8.
9. "Figma-first / frames precede code" stated as a full rule (not a link) in 4 living places — ios/README:8, STATUS:32, ROADMAP:49, FIGMA.md:76.

### B6. Spec 14 (until built) / iOS-side owners

1. Dormancy rule (`window == nil` → stored, excluded from `/rating` body and snapshot) — spec 14 §1 (owner) + push spec:21 + CONTEXT:38.
2. Template list + Range prefills (Cycling 6–10am…) — four lists: spec 14:137–143 (owner-confirmed table), README:26–31, CONTEXT:10, GLOSSARY:75–76. A fifth template = four edits.
3. Card chips rule (first 3 displayMetrics, valued at best-window start hour) — Guidelines:122 + spec 14:82–83.
4. Card sublabel must match push copy word-for-word — spec 14:76,221 + push spec:27 (pointer-ish; listed for completeness).
5. Push opt-in surfaces (Settings "Notifications" row + one-time dashboard callout) — push spec:13 (owner) + FIGMA.md:82 + ROADMAP:13.
6. XCUI launch args (`UITEST_LOCATION`/`UITEST_LOCATION_DENIED`/`UITEST_RESET`) — ios/README:4 (proposed owner) + push spec:34.
7. Product one-liner "worldwide, UAE-first in marketing only" — verbatim in README:3 + CONTEXT:5.
8. README:14's partial hourly-metric list is already lossy (omits darkness/tide/swell/douglas) vs the CLAUDE.md `hours[]` contract.

---

## Non-findings (recorded so the cross-check doesn't re-flag them)

- Swift doc comments in `ios/TimeIt/` (ForecastResponse.swift:13, HourlyWeather.swift:4–8, APIError.swift:4–9, TimeDeriver.swift:3) mirror contract prose — sanctioned client mirrors in *code* per ADR-0007; not counted.
- The iOS side has **zero** leftover "flexi" (md/swift/plist grepped) — that half of the 405bbba sweep was clean.
- Restatements inside frozen files (`docs/adr/`, `completed/`, `docs/audit/`, `docs/review/`) — excluded by design; history is not expected to track current truth.

## Reading of the evidence (for the cross-check, not a directive)

Five natural owners already exist and are mostly declared in the docs themselves (vendor → `meteosource/README.md`, status → ROADMAP, wire/engine contract → CLAUDE.md, terms → CONTEXT, design → FIGMA.md). Nearly every finding is a restatement *into* CLAUDE.md/CONTEXT/README rather than a missing home. The 11 section-A items are the proof restatements decay; A1–A4 (GLOSSARY vs spec 14) are the most consequential — an agent reading GLOSSARY today builds the wrong first-launch model.
