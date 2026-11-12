# Implementation spec — fresh-eyes UX: copy and visual faults (build 10, Lane SPEC)

> Living work order, created 2026-11-12 (Lane SPEC of the [build-10 round](build-10-lanes.md)). Answers the [spec request](spec-request-fresh-eyes-ux.md) §4/§6. Evidence: [NOTES.md](../../research/fresh-eyes-2026-11-11/NOTES.md) (build 8, fake data) and [ADDENDUM-build9.md](../../research/fresh-eyes-2026-11-11/ADDENDUM-build9.md) (build 9, real backend; `b9-*.jpg` beside it). Owner page (one ask per fault, a/b/c): https://claude.ai/artifact/1w3p7Kw3zf7Fb4Quf3CsvC. Status home once ruled: [ROADMAP](../ROADMAP.md) (proposed row in §7 — the orchestrator lands it). Nothing here is ruled yet; every fault carries a ruling slot.

## §1 Goal and scope

Turn each copy/visual fault the fresh-eyes tester found into a **named transition** in one of six state maps (request §4), so each fix is a state that gains copy, a guard or a surface, not a patch on a screen.

**This lane's notes:** 1, 2, 5, 6, 7, 9, 10, 11, 12, 14, 15, 17, 20, 22, 23, 25, 26, 28, 29, 30, 35, plus the build-9 "New" items that are copy or visual (B9-2, 3, 4, 6, 7, 8, 9).

**Not re-specced here (cross-references only):**
- **Lane FIXES:** 3, 4, 8, 13, 16, 21, 27, 32, 34, 36.
- **Lane MANAGE (shipped):** 24, 31, 33, 38.
- **Lane CACHE (shipped):** 37.
- **Owner question, ADR-0011:** 18/19 (+ B9-5).
- **Lane FIXES / server:** B9-1, the UV `?? 0` false-Perfect.
- **Process note, not a fault:** B9-10.

**Constraints:**
- **No engine or rating-rule change.** The verdict/score independence rule holds ([ADR-0011](../../adr/0011-day-score.md)).
- No wire change. °F and mph are display-only conversions, like the shipped wind-unit setting.
- **Figma-first** for anything that adds an element or changes layout ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)).
- **Vocabulary rule:** new on-screen copy never says "range" or "threshold" ([CONTEXT.md](../../CONTEXT.md)).

**Classification used below:**
- **Copy-only** means only the words, a glyph or a colour on an element that already exists, or a stock system dialog. There is no new element and no layout change, so it can ship without a frame if the owner rules so.
- **Needs a frame** means a new element, a layout change, or a new control.
- **Scope:** **standalone** ships in a build-10+ lane. **Item 13** means the fault is replaced by an approved onboarding-v2 frame.
- **What the item-13 frames cover:** the Figma read pass on 2026-11-12 (the "Onboarding Wireframes" page, read-only) found that they cover **first run only**: Welcome, hobby pick, Q1 "When do you usually …?" with a Recommended option and a Night option, the location ask, the city-picker refusal path, the verdict reveal and the dashboard landing. The regular wizard still authors every later Activity. Its deprecation is a ROADMAP §Deferred expectation, not a ruling. So wizard faults are **standalone**.

### Closed — no ruling needed

| Note | Why |
|---|---|
| 12 | Fixed by build 9: the Review preview is neutral and live (addendum). |
| 30 | Fixed by build 9: the overnight preview axis runs 8 → 2 (addendum). |
| 22 | Fixture artefact: real Dubai reads 22–29 °C. |
| 15, 17 | Positive notes (callout timing; the detail screen). Keep as is. |

## §2 State maps (from the code as it exists, `main` `d0e7493`)

### Map A — Location × home × forecast × activities (Dashboard, Settings)

**Inputs:**
- `authorizationStatus`: notDetermined / denied / restricted / authorized.
- `preferences.homeLocation`: nil / city.
- GPS fix: none / arrived.
- Forecast: loading / loaded / failed.
- `store.activities`: 0 / ≥1 live / all dormant.

**The dashboard's content ladder** (`DashboardView.content`). The first match wins:

| State | Guard | Screen shows |
|---|---|---|
| A1 `firstLaunch` | 0 activities | Add capsule + "Time It checks weather conditions for any activity you create. Start with your first one." Header "NO LOCATION" when nothing resolves. **No location hint, whatever the permission.** |
| A2 `dormantList` | ≥1, none live | Dormant list |
| A3 `noLocation` | ≥1 live, no home / fix / cached | Two skeleton cards + "No location yet" + Enable Location / Place your own location |
| A4 `loading` | fetch in flight | "Checking conditions…" |
| A5 `error` | fetch failed, no cache | Error view |
| A6 `cards` | forecast | Card list |

**Settings home row** (`SettingsView.homeLocationSection`):
- The row reads `homeLocation?.name ?? "Using current location"` **regardless of `authorizationStatus`**. The denied case is note 3 → FIXES.
- "Use current location" sets `homeLocation = nil` with no guard. That is note 8 → FIXES.

**Transitions with faults:**
- **T-A1 (note 1):** cold launch → `requestInitialLocationPermissionIfNeeded()` fires the system prompt over A1 with no prior explanation. → **Item 13** (Welcome, then the location ask with its why).
- **T-A2 (note 2):** denied + 0 activities → A1, which outranks A3, so the "pick a city" prompt is unreachable until an Activity exists.
  - **Build 10's purge empties every install**, so every existing user whose location is denied lands here on first launch.
  - → **Standalone** residual (A1 gains a location line when nothing resolves) + **item 13** for new installs.
- **T-A3 (note 5):** home = city → the "Use current location" row appears as a bare `Button("…")` with no icon, under the iconed "Set home location" `Label`. → copy-only (glyph).
- T-A4 (notes 3, 8, 13): **FIXES**.

### Map B — Notification permission × Settings switch × home callout

**Inputs:**
- `registration.isEnabled`.
- `snapshotHome()` (home or fix): yes / no.
- iOS authorization result: granted / denied.
- `pushCalloutDismissed` / `pushCalloutResting`.

| State | Switch | Callout | Prompt |
|---|---|---|---|
| B1 off, home known | off | full callout (≥1 activity) | flip → iOS prompt → B3 / B2 |
| B2 off, iOS denied | stays off | callout | none (re-flip no-ops) |
| B1′ off, no home | off → `.needsLocation` | callout | notDetermined → location prompt; otherwise **the city picker opens with no line saying why** |
| B3 on | on | gone (bell resting) | — |

**Transitions with faults:**
- **T-B1 (note 6):** the footer under the switch reads only "Perfect window alerts". It does not say what arrives or when.
- **T-B1′ (note 6):** switch → city picker with no reason given.
- Both are copy-only and **standalone**. Item 13 has no notification frame.
- The switch not flipping on a tap, the callout opening only Settings, and the missing confirmation after enabling are note 27 → **FIXES** (hardware check first).

### Map C — Wizard step validity (`EditorStep`, five steps)

| Step | Complete when | Hint shown when incomplete |
|---|---|---|
| C1 Name | label non-empty **and** `iconSymbol != questionmark.circle` | **none** (note 9) |
| C2 Metrics | ≥2 metrics + every threshold parses | "Pick at least two" (MANAGE) |
| C3 Priority ("What matters most?") | ≥1 pressed (or nothing judgeable) | "Press at least one." Explainer: "Pressed ones matter most. The rest still show." |
| C4 When ("When do you go?") | from ≠ to and confirmed | "Start and end can't be the same." |
| C5 Review | the draft builds | — |

`ActivityDraft` prefills a new draft to 6–10am whatever the icon is.

**Transitions with faults:**
- **T-C1 (note 9):** name typed, no icon → Next is off and silent.
- **T-C1b (note 9):** Beach & Water has no beach/sun glyph. **T-C1c (note 29):** Night has one glyph.
- **T-C2 (note 10, residual):** Moon Phase is ticked with no word on what it does. **T-C2b (note 10):** the slider is twitchy, with no nudge and no typed entry.
- **T-C2c (B9-2):** opening a tile's slider as a full-width row reflows the grid under the finger.
- **T-C3 (B9-3):** the explainer doesn't say what "matters most" does. In domain terms, pressed = `required`: it can make an hour Bad. Unpressed can only drop Perfect to Good. Moon Phase drops out of this step silently.
- **T-C4 (note 11):** no helper line, no "All day", and a silent 6–10am default.
- **T-C4b (note 29):** from > to (overnight) is accepted with no "ends next morning" line.
- **T-C5 (B9-4):** the Review title reads "First activity created" / "Activity created" and the line "… is on your dashboard." **before** Save.
- **T-C6 (note 35):** ✕ with unsaved changes → dismissed silently (new and edit alike).
- **T-C7 (B9-8):** at AX5 the pinned Next overlaps the last list row.

### Map D — Detail span shift (`ActivityDetailView` hero + `SpanScoring`)

**Inputs:**
- −/+ or a carousel drag (span ≠ Range).
- The "Score {span}" capsule.
- Return button or a ring tap.
- Day jump.
- The Range has passed.

| State | Ring numeral | Word under ring | Row 2 |
|---|---|---|---|
| D1 at Range | day `score` | day verdict ("Perfect" / "Good" Semibold tint; else "No Window" Regular light red) | — |
| D2 span previewed, unscored | **day score (unchanged)** | **day verdict (unchanged)** | "Score 10am – 6pm" capsule |
| D3 span scored | span score | span verdict | "Scored 10am – 6pm" |
| D4 Range passed, no data | empty ring | **"No Window", light red** | row 1 "Your range 6 – 10am · Time passed" |

The metric cards **average the chosen hours**. Nothing on screen says so.

**Transitions with faults:**
- **T-D2 (note 23):** D1 → D2 keeps a "Perfect" that does not describe the hours on screen.
- **T-D4 (B9-6):** a day whose hours have passed reads as a bad-weather day (red word).
- **T-D5 (note 20):** the cards don't name the hours they average. Hour chips are not tappable.
- **T-D6 (note 25):** when scrolled, the title bar floats over a blurred ring.

### Map E — Card (`ScoreRingCardView` + dashboard chevron overlay)

**Inputs:**
- Chevron tap (per-card `collapsed` memory).
- Card tap → detail.
- Dot tap.
- Appearance.

| State | Chevron | Shows |
|---|---|---|
| E1 expanded | `chevron.down` | ring + score + hour strip + week dots. **No verdict word** (wordless v2 card, owner ruling 2026-09-21). Words only in VoiceOver ("Perfect, score 84 out of 100"). |
| E2 collapsed | `chevron.down` turned −90° (points right) | ring + strip, no dots |

**Transitions with faults:**
- **T-E1 (note 14):** first sight of E1 → no legend for green/orange/red and no verdict word.
- **T-E2 (note 26):** E1 → E2 turns the chevron to point **right**, which iOS reads as "navigate". The card tap really does navigate, so two right-ish affordances compete.
- **T-E3 (note 28):** the header reads "28°" with no unit. The approved onboarding dashboard frame (07) already draws "28°C".
- Dot tap opening today (note 16) → **FIXES**.

### Map F — Appearance switch while a screen is live, and the opening

**Inputs:**
- The header appearance control or Settings → Appearance (`preferences.appearance`, applied by `AppearanceController`).
- Cold launch.

| State | What rebuilds |
|---|---|
| F1 switch on Home / Settings | the whole window re-renders from tokens (correct on build 9, `b9-20*`) |
| F2 switch while on the detail | not reachable from the UI (the control lives on Home + Settings only). The old glitch was note 34 → FIXES. |
| F3 cold launch | opening sequence: a 1.0 s hold (POLISH) → converge → "Time it" wordmark → reveal. Every launch. |

**Transitions with faults:**
- **T-F1 (B9-9):** the header control is an unlabeled half-filled circle. VoiceOver already says "Switch to Dark / Light". The visible control has no word.
- **T-F3 (B9-7):** the opening plays on every cold launch, and the wordmark's case ("Time it") differs from the app's "Time It". **Owner question, not a fault:** POLISH lengthened the opening and the owner accepted ~5.5 s. The approved Welcome frame also uses the lowercase mark.

## §3 Per-fault change list (priority order; ruling slot per fault)

Sev = the tester's severity (B9 items carry the addendum's implied severity).

| # | Note | Surface · map | Current → proposed | Class | Scope | Recommended fix (option a) | Ruling |
|---|---|---|---|---|---|---|---|
| 1 | 14 (Sev 3) | Card · T-E1 | wordless card, no legend → a one-time legend line under the first card ("Green Perfect · Orange Good · Red outside your limits"), dismissed on first detail visit | needs a frame | standalone (item 13's verdict reveal teaches it once, for new installs only) | a: one-time legend line · b: rely on item 13's reveal · c: reopen the wordless ruling, add the verdict word | **b** |
| 2 | 6 (Sev 3) | Settings · T-B1/T-B1′ | footer "Perfect window alerts"; the picker opens silently → footer "A morning summary of your best hours, and an alert when a Perfect window opens." Picker headline line when opened from the switch: "Pick a city so alerts know where to look." | copy-only | standalone | a: both lines · b: footer only · c: keep | **a** |
| 3 | 2 (Sev 2) | Dashboard · T-A2 | empty home, no location, no hint → A1 gains "No location yet · **Pick a city**" (opens the picker) under the invitation when nothing resolves | needs a frame | standalone (build-10 purge makes it common) + item 13 for new installs | a: standalone now · b: item 13 only · c: keep | **b** |
| 4 | 1 (Sev 2) | Dashboard · T-A1 | system prompt before any welcome → Welcome, then the location ask with its why | needs a frame (**approved**) | item 13 | a: item 13 as drawn · b: interim one-line pre-prompt now | **a** |
| 5 | 23 (Sev 2) | Detail · T-D2 | stale "Perfect" while previewing a span → in D2 the ring and word dim to secondary until scored (or until return) | copy-only (colour) | standalone | a: dim while unscored · b: score automatically when the row settles (one server call per settle) · c: keep | **a** |
| 6 | B9-6 (Sev 2) | Detail · T-D4 | passed day = red "No Window" → word "Time passed" in secondary, no red; row 1 drops its suffix | copy-only | standalone | a: as proposed · b: keep red, enlarge "Time passed" · c: keep | **— (owner 2026-11-12: "never show an empty passed-day screen"; what to show when the time has passed is an open conversation)** |
| 7 | 20 (Sev 2) | Detail · T-D5 | cards average unnamed hours → a caption above the cards: "Average, 6 – 10am" (follows the span) | copy-only | standalone | a: caption · b: caption + tappable hour chips (frame) · c: keep | **b (owner: "let's try to sim" — chips built in the mini-edits lane, owner rules from screenshots)** |
| 8 | B9-3 (Sev 2) | Wizard · T-C3 | "Pressed ones matter most. The rest still show." → "Pressed ones can turn a day red. The rest can only take Perfect down to Good." + "Moon Phase shows on your card but isn't judged." when picked | copy-only | standalone | a: both lines · b: first line only · c: keep | **c** |
| 9 | B9-4 (Sev 2) | Wizard · T-C5 | "created" before Save → new: "Your first activity" / "Your new activity". Line: "Save to add it to your dashboard." Edit keeps "Your activity". | copy-only | standalone | a: as proposed · b: keep titles, change the line only · c: keep | **a** |
| 10 | 9 (Sev 2) | Wizard · T-C1 | silent icon gate → "Pick an icon too." (the gate-hint idiom) once a name is typed; add a beach/sun glyph to Beach & Water | copy-only | standalone | a: hint + glyph · b: hint only · c: keep | **a (owner: an icon is required no matter what; glyphs from SF Symbols)** |
| 11 | 11 (Sev 2) | Wizard · T-C4 | no helper, silent 6–10am → helper under "When do you go?": "We only check these hours, every day." | copy-only | standalone (item 13's Q1 presets are first-run only) | a: helper line · b: helper + Q1-style presets incl. "All day" (frame) · c: keep | **a** |
| 12 | B9-2 (Sev 2) | Wizard · T-C2c | the grid reflows under the finger → tiles keep their grid positions; the open tile's slider sits below the grid | needs a frame | standalone | a: slider below the grid · b: slider in a sheet · c: keep | **b? (owner asked what "sheet" means — held until answered)** |
| 13 | 35 (Sev 2) | Wizard · T-C6 | ✕ discards silently → system dialog "Discard this activity?" / "Discard changes?" only when the draft changed | copy-only (stock dialog) | standalone | a: both new and edit · b: new only · c: keep | **a** |
| 14 | 7 (Sev 2) | Settings · units | km/h + knots, no °F → add mph now; °F as a Settings row converting every temperature surface (display-only; stored limits and the wire stay °C) | needs a frame (°F); mph alone is copy-only | standalone | a: mph now, °F frame later · b: both now · c: neither (UAE-first) | **a (°F parked in docs/post-release)** |
| 15 | 10 (Sev 2, residual) | Wizard · T-C2b | twitchy slider, no fine control → −/+ nudge beside the readout | needs a frame | standalone | a: nudge buttons · b: tap the readout to type · c: keep | **c** |
| 16 | 29 (Sev 1–2) | Wizard · T-C4b/T-C1c | overnight is silent; one Night glyph → line "Ends next morning" when from > to; two or three more night glyphs | copy-only | standalone | a: line + glyphs · b: line only · c: keep | **a (SF Symbols)** |
| 17 | B9-8 (Sev 2) | Wizard · T-C7 | at AX5 the Next button overlaps the list → a layout bug against the shipped design, no new frame | no frame (layout bug) | standalone | a: route to FIXES · b: fold into a later AX pass | **a (done, FIXES item 9)** |
| 18 | 28 (Sev 1) | Dashboard header · T-E3 | "28°" → "28°C" (as the approved onboarding dashboard frame already draws) | copy-only | standalone | a: add the unit · b: keep | **a** |
| 19 | 26 (Sev 1) | Card · T-E2 | collapsed chevron points right → down when dots hidden, up when shown (reverses the 2026-10-02 chevron ruling) | copy-only (glyph) | standalone | a: down/up · b: keep down/right | **b** |
| 20 | 25 (Sev 1) | Detail · T-D6 | title floats over a blurred ring → solid material title bar once scrolled | needs a frame | standalone | a: solid bar · b: fade the hero out under the bar · c: keep | **c** |
| 21 | 5 (Sev 1) | Settings · T-A3 | "Use current location" has no icon → `location` glyph, aligned with the row above | copy-only (glyph) | standalone | a: add glyph · b: keep | **a (the picker itself: parked in docs/post-release, owner 2026-11-12)** |
| 22 | B9-9 (Sev 1) | Header · T-F1 | unlabeled appearance control → keep Apple's half-circle glyph (VoiceOver already labels it) | copy-only | standalone | a: keep as is · b: add a small visible label | **a** |

### Owner questions (no fault row) — **ruled 2026-11-12: Q1 b, Q2 b (wordmark case still open)**

- **Q1 — the score beside "Perfect" (18/19, B9-5; ADR-0011).** Real data shows "20 · Perfect" for one green hour in five, and the Review preview shows it during creation.
  - a: name the Window beside the verdict ("Perfect 10–11pm"). Copy plus a small frame, no engine change.
  - b: open an ADR-0011 amendment on how the score and verdict are presented.
  - c: keep.
- **Q2 — the opening (B9-7).**
  - a: keep it on every cold launch (as ruled).
  - b: play it on the first launch only, then a plain fade.
  - The same question asks the wordmark's case: "Time it" (the approved Welcome frame, the beta copy) or "Time It" (everywhere else).

**Rulings 2026-11-12 (owner, from the page):** 1b 2a 3b 4a 5a 7b 8c 9a 10a 11a 12b 13a 14a 15c 16a 17a 18a 19b 20c 21a 22a Q1b Q2b; 6 unruled (conversation), 12 held on a question. Work: copy lane = 2, 5, 9, 10, 11, 13, 14 (mph), 16, 18, 21; mini-edits sim lane = 7 chips + Q2 opening-once; Q1 = ADR-0011 amendment draft (orchestrator); parked in `docs/post-release/` = °F, the location picker rethink, 12 (if b holds), 6.

**Counts (open faults: 22):**
- **By class:** copy-only 15 · needs a frame 6 (one already approved: note 1) · layout bug, no frame 1.
- **By scope:** standalone 21 · inside item 13 1 (note 1). Note 2 is split: standalone residual + item 13.

## §4 Tests (one pin per transition; written against the owner's rulings)

**Unit:**
- `DashboardContentLadderTests.testEmptyStoreWithNoLocationShowsPickCityLine`, if fault 3 = a.
- `SettingsCopyTests.testNotificationsFooterNamesDigestAndAlert`.
- `SettingsCopyTests.testCityPickerFromSwitchShowsReason`.
- `EditorStepTests.testNameStepHintWhenIconMissing`, and none once an icon is chosen.
- `PriorityChoiceTests.testExplainerCopy`.
- `PriorityChoiceTests.testMoonPhaseNoteShownWhenPicked`.
- `EditorReviewTitleTests`: new-first, new-later, edit, and no "created" wording.
- `EditorWhenStepTests.testOvernightLineWhenFromAfterTo`, and absent for same-day.
- `EditorDismissTests.testCleanDraftDismissesWithoutDialog`.
- `EditorDismissTests.testDirtyDraftAsksToDiscard`.
- `DetailHeroStateTests.testPreviewedSpanDimsRingAndWord` (D1 → D2 → D3 → return).
- `DetailHeroStateTests.testPassedDayReadsTimePassedNotNoWindow` (D4).
- `MetricCaptionTests.testCaptionNamesAveragedHours`, following the span.
- `HeaderTempTests.testUnitSuffix`.
- `CardChevronTests.testGlyphPerState`.
- `UnitsTests.testMphConversion` (and °F if 14 = b).

**XCUI** (one per surface):
- Denied + empty store → the "Pick a city" line is visible and opens the picker.
- Wizard name-without-icon hint.
- Wizard ✕ on a dirty draft shows the dialog.
- Detail +1 dims the word, and scoring restores it.

## §5 Acceptance

- [x] Re-run against the real backend — done 2026-11-11 by Lane RERUN ([ADDENDUM-build9.md](../../research/fresh-eyes-2026-11-11/ADDENDUM-build9.md)).
- [ ] The owner rules every row in §3 and Q1/Q2 on the owner page; the rulings are recorded in this file.
- [ ] The needs-frame rows that are ruled in are drawn on Mess around and approved (ADR-0008).
- [ ] The copy-only rows land test-first in one lane; both suites stay green.
- [ ] The tester's route is re-walked on the phone for faults 1–13.

## §6 Hardware checks owed (from the request §5)

These belong to FIXES, but they gate faults 2 and 13:
- Note 27, the switch tap.
- Note 32, the edge swipe-back (build 9 passed it on the simulator).

## §7 Proposed ROADMAP row (the orchestrator lands it — this lane may not edit ROADMAP)

| 21 | **Fresh-eyes copy & visual pass** — the 22 open faults of the [fresh-eyes spec](current/implement-spec-fresh-eyes-ux.md) (15 copy-only, 6 frame, 1 layout bug) + owner questions Q1 (score beside Perfect, ADR-0011) and Q2 (opening/wordmark) | both | spec written 2026-11-12 (Lane SPEC); owner rulings next (owner page linked in the spec); copy-only rows → one TDD lane; frame rows → Mess around after rulings |
