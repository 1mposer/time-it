# Design-lead report — depth & polish pass (2026-10-06)

> **Status:** owner-ruled 2026-10-06 ("all a", ruling 2 amended) — rulings of record: [FIGMA.md §12](../../design/FIGMA.md); item: [ROADMAP 17](../ROADMAP.md). This file is the **source material for the Figma drawing pass and the spec**, not a decision record: where it and §12 differ, §12 wins (notably ruling 2: the gear goes with **no long press** — tap opens the detail, editing lives in the detail's rows). Written by an Opus design lead working read-only (repo + Figma), vetted by the auditor against the code; five items went back once and the revised sections replace the originals below. Values here are proposals until drawn and approved (design truth lives in Figma, shipped truth in code).

Brief given to the lead: the owner's build 7 audit (A–E below), "quiet surfaces like Apple Weather", references (Not Boring) Weather / Future Pro / Klarna, the app's personality ("hobbyists who enjoy minimalist simplicity"), iOS 17 target, light ships first with dark designed now, wizard + settings = recommendations only.

## 1. Map (verified by the auditor 2026-10-06)

- **Card:** `ScoreRingCardView` — fixed detail-column heights 65 / 107; 58pt trailing clearance for the gear + chevron that `DashboardView` overlays outside the NavigationLink; the card shadow (black 8%, r3, y1 + a 0.5pt 6% hairline) is hand-copied in six views.
- **Ring:** `ScoreRingView` — a nil score draws only the track, and the track (`Theme.timelineTrack`, #f2f2f7) equals the app background, so the empty ring is near-invisible on a white card. Half of why the passed-Range card reads broken.
- **Detail:** `ActivityDetailView` — "No Window" takes its red from `Theme.ratingTint(nil) → badRed`, a mapping shared with the card ring and the `.unknown` hardening; the stepper has a `Spacer` either side of the hour label, which pins − and + to the column edges.
- **Theme:** flat sRGB hex, no dark values; the header gradient mirrors `Semantic gradient/*` by hand.
- **Dashboard:** hard-edged gradient header, 0.5pt divider, flat grey below.
- **Persistence:** `PreferencesStore` (UserDefaults; `collapsedCards` is the precedent). **No forecast or day cache exists.**
- **Dynamic Type:** none — 82 `.system(size:)` uses, one text-style use.
- **UI tests pin:** `score.*` / `detail.score` labels incl. "No Window, score 1 out of 100"; `detail.selectedHour` as a staticText; `gear.*` (seven uses) and `cardChevron.*`.
- **Figma rules in play:** §4 "header gradient is a temperature encoding for the header only"; §3 "elevation: exactly two levels"; §11 "the card is wordless".
- **Anticipates the work (lead's live read, auditor-unverified):** `Semantic` holds `surface/card-elevated` (Light #fff / Dark #2c2c2e) — not listed in §3; one effect style `TimeIt/Card Shadow` (r3 y1 8%). Verify at the start of the drawing pass.
- **Owner taste evidence (Mess around `179:5`):** an off-white onboarding screen with white pill rows and a black capsule CTA; a dark list with one glowing gradient weather module.
- **Could not find:** any day cache; dark `gradient/*` values (Light = Dark today); any shadow token beyond Card Shadow; frames for the passed-Range card or either detail null state; a Dynamic Type spec.

## 2. Lenses

Time (what the screen says at 5pm, across first launch, refetches, date rollover, edits) · Body (dusk, one-handed, two-second read) · Reach (Dynamic Type, VoiceOver honesty about a cached forecast, Reduce Motion, contrast of the empty ring) · Failure (a cached score that lies; a red word that blames the user's day) · Subtraction (the gear, redundant numerals, the orange CTA).

## 3. Vocabulary (revised — one pair, every surface)

| Surface | Range passed, cached | Range passed, no cache | Bad day |
|---|---|---|---|
| Card ring caption (replaces "Score") | "Passed" | "Passed" | "Score" |
| Detail hero word, `text/secondary` | "Passed" | "Passed" | "No Window" |
| VoiceOver | "Passed. Forecast from earlier today: Perfect, score 86 out of 100." | "Passed. Back tomorrow at 6am." | "No Window, score 31 out of 100." (unchanged) |

"No Window" keeps its exact string so the detail is true on any jumped day ("Not today" would be false on a jumped Thursday). The card never prints a verdict word; the caption names what the ring holds. No UI-test strings change.

## 4. Proposals

### A. Card after the Range has passed — "Passed" (ruling 1a)

- **A1, cache exists:** arc in the verdict colour at 40%, numeral full tier colour, caption "Passed", strip = cached per-hour tiers at 35% (the detail's "not selected" idiom) with numerals kept, today's dot = cached verdict. Crossfade 0.25s when a refetch flips live → cached; Reduce Motion = instant.
- **A2, no cache:** dashed track (`separator`, 1.5pt, dash 3/3), no numeral, caption "Passed", one line in the strip slot, 13 Regular `text/secondary`: "Back tomorrow at 6am" (Range start). Glyph-free; if a glyph is wanted later, `clock` 15pt (true at any hour). Nocturnal Activities rarely reach this state (day 0 is tonight).
- **Cache:** key = Activity id + forecast-zone local date + a signature of the Range and thresholds + the 2dp location; value = rating, score, local start/end hours, per-hour tiers. **Never store `startIndex`/`endIndex`/`dayIndex`** (they re-base every fetch — the #6d index-dedup bug is the precedent). Keep the snapshot covering the most Range hours (ties → latest). Invalidate on edit, location change, date rollover. One cache, three readers: card ring, today's dot, the detail's day-0 hero. No server work.
- Alternate (not chosen): dimmed card + clock glyph, wordless. Killed: a passed-Range banner above the list.

### B. Card hierarchy — B1 "Thread" (ruling 3a), gear removed (ruling 2a, amended)

- Title 17 Semibold (`TimeIt/Card Title` → 17 Semibold). Strip 5pt, radius 2.5, 2pt gaps. Numerals 11 Regular `text/secondary`. Rhythm: title→strip 14 (lg), strip→numerals 4 (xs), numerals→dots 16 (xl). Padding 16. Heights: 58 text column → 65 collapsed (ring column sets it), 108 with dots.
- Fit with the gear gone (chevron only, 24 clearance): 247pt for icon + name + chip; a nocturnal chip (~88) leaves ~125pt ≈ 13 characters at 17 Semibold.
- (Gear-kept fallback, superseded by ruling 2: title 16 Semibold, ~12 / 10 characters beside a day / night chip.)
- **Editing after the gear (per the amended ruling): tap → detail → Edit range / Edit metrics rows.** Two taps, good thumb reach, high discoverability once in the detail. The lead's long-press menu is **not** adopted.
- B2 "Ends only" (alternate): title 16, strip 6, numerals at the two ends, rhythm 10/4/14. B3 "Big name" (killed): 20pt title does not fit beside a night chip.
- All variants survive onboarding 06/07 unchanged (same component).

### C. Detail hero — two grey states with a way forward (ruling 4a)

| State | Wire signal | Word | Ring | Line under it |
|---|---|---|---|---|
| C1 Range passed | `score` nil on a windowed Activity | "Passed", 12 Semibold `text/secondary` | cached ring (as A1), else dashed | "Tomorrow looks Perfect" |
| C2 Bad day | `rating` nil, `score` present | "No Window", `text/secondary` | real score, arc `rating/bad` | "Thursday looks Good" |

- **Line rule:** nearest day forward of the shown day that is Perfect, else Good; text "<Day> looks <Perfect|Good>", 13 Medium `accent/interactive`, 44pt hit via padding; nocturnal wording "Tomorrow night" / "<Day> night"; tap = the existing day-jump; VoiceOver button "Jump to Thursday, Perfect". None qualifies → static "No window this week" in `text/secondary`, no button trait. One mechanism in both states, no capsule (the dots row already gives the one-thumb jump).
- **Placement:** C1 in the hero's empty strip slot (height unchanged); C2 a new row under the red pills, 8pt gap (hero +28).
- C1's stepper keeps working over today's remaining hours (pills hidden outside the Range, per the §11 ruling). Red stays only on metric values and hour pills. **The fix lands at the hero call site, never in `Theme.ratingTint`** (its `.unknown → never favourable` rule must hold).
- Alternate: one shared grey "No window". Killed: illustration + paragraph.

### D. Hour stepper — D1 "Hug and glide" (ruling 5a)

- Cluster `[− 8pt label 8pt +]` centred over the strip column. Buttons 32pt visual circles in `surface/background`, 44pt hit targets overlapping the gap via a negative-padding pair (visible edge→label 14pt).
- Label = one concatenated `Text` (keeps `detail.selectedHour` and its tests): numeral 28 Semibold monospaced digits (`TimeIt/Score`), suffix "am"/"pm" 15 Medium `text/secondary`.
- Motion: numeral rolls with `contentTransition(.numericText())` (counting down on −); cluster width animates on a ~0.25s no-bounce spring; "8am"→"10am" adds ~14pt so each button moves ~7pt, inside its target during rapid taps. **Reduce Motion:** no roll, no glide — label crossfades 0.15s, buttons snap (gate explicitly; whether `numericText` honours Reduce Motion on its own is unverified). AX sizes: cluster drops below the ring, full width.
- D2 "Fixed slot" (alternate): slot sized to "12pm", no motion, 7–14pt of air. D3 "Leading cluster" (killed).

### E. Depth — "quiet" (ruling 6a)

Common thread of the references: one atmospheric ground, surfaces that float on it, one hero number, calm words for empty moments. Apple Weather adds the quiet: uniform low-contrast modules, the ground carrying the meaning — here, temperature.

1. **Ground (L0).** The header gradient loses its hard edge. Dashboard (393×852 frame; header 0–219, first module top 229): band at 100% from 0–150, linear alpha fade to `surface/background` 150–260; tint at the first card's top (y 229) = 28% of the band's end colour (cool #68d7fc · mid #f2c95c · hot #fa9c86); 0% at every verdict mark (first strip ≈ y 281 with B1, dots ≈ 315). The divider goes. The wash **scrolls with the content** (pinned, cards would scroll into it). Dark: same geometry, new dark `gradient/*` values (~40% luminance) fading to #000. **Detail: no wash** — the dots sit on the ground from y 110; a wash would have to end above 110 and would only tint the nav (a coloured bar, which the HIG discourages). If wanted anyway: 0–50 at 30%, 0% by y 104. Honest consequence: a header with a 110pt soft edge, not a full-screen sky — the verdict-colour rule forbids the fuller Klarna/Future ground while red/amber marks sit near the top.
2. **Module (L1, the card level).** Light: `surface/card`, radius 16, **no hairline**, one effect style `TimeIt/Card Float` (y4, blur 16, black 6% — tune on device) replacing the 3/1/8% shadow + hairline everywhere. Dark: `surface/card-elevated` (#2c2c2e), **no shadow** — lightness carries elevation.
3. **Recess (inside a module, not an elevation).** Stepper + strip well, metric gauges: `timeline/track` fill, radius 10, no shadow, no stroke (Future's nested lighter card, read as a recess).
4. **Sheet (L2).** Wizard + settings, the system sheet; unchanged. Two levels hold.
5. **Separation** by space: 12 between modules, 24 before a group; hairlines only inside lists (Edit range / Edit metrics); materials only on floating chrome (settings, back) as `.thinMaterial` circles, solid `surface/card` under Reduce Transparency.
6. **One big number per screen.** Detail: the score — hero ring 64 → 80, numeral 28. Dashboard: see F.
- Alternate: translucent material cards on the gradient (contrast shifts, verdict colours tint through). Killed: stronger shadows/borders on flat grey.
- iOS 26 (later): Liquid Glass would take the back/settings/chevron chrome and the scroll-edge effect would replace the fade; content layer unchanged.

### F. Header hero — temperature as the numeral (ruling 7a)

The lead's challenged premise: "depth is about surfaces" — the bigger flatness is hierarchy. The dashboard's boldest type (`TimeIt/Header Time`, 60 Bold) is the clock, which the status bar already shows, while the ground encodes temperature. Make temperature the giant numeral (60 Light, on its own gradient) and demote the time to the meta line; then the ground, the big number and the cards' scores speak one language.

### G. Wizard and settings (parked — recommendations only)

Sheets stay plain `surface/background`, no ground. Rows → 52pt cards, radius 16; section headers → 13pt secondary labels; step pills → a quiet 4-segment progress line + step title; the orange "Save Activity"/"Review" fills → `accent/interactive` (orange already means Good; one colour must not mean two things).

## 5. Feasibility

- **A:** iOS 17 ok; no server work; new small UserDefaults store (PreferencesStore-style) with three readers (`WeekDots.dots` derives from `activity.days` — today's dot needs the cache); new unit tests for the key + invalidation; `score.*` UI test changes only if VoiceOver copy changes.
- **B:** trivial; recompute or (better) make the fixed heights intrinsic; removing the gear breaks the seven `gear.*` UI-test steps — editing stays reachable through the detail.
- **C:** call-site only; "No Window, score 1 out of 100" labels unchanged; the jump line reuses the existing day-jump.
- **D:** `numericText` fine on iOS 17; the concatenated-Text keeps `detail.selectedHour` a staticText; Reduce Motion gated explicitly.
- **E:** `LinearGradient` + `.thinMaterial` + the elevated surface; dark blocked in code until Theme becomes adaptive (light ships on today's hex + the new tokens); no identifier changes; low perf risk.
- **Dynamic Type (ruling 8a):** real work on the touched views — text styles + intrinsic heights.

## 6. Figma plan (draw before code — ADR-0008)

- **Change:** ring card `458:394` (cards `458:396` / `458:417`) + dark `487:400` — B1, no gear, Card Float; Dashboard Loaded `111:2` / Push Callout `266:5` + dark `121:2` / `266:1562` — ground wash, new card style, header numeral swap (F); Detail v3 `456:358` `464:2348` `487:819` `487:897` `508:417` + dark `491:711` `491:773` `491:835` `491:897` `509:836` — D1 stepper, recess well, ring 80; Onboarding 06/07 `463:2251` / `464:500` — re-instance the card only.
- **New:** Card Passed A1 + A2 (light + dark); Detail C1 + C2 (light + dark); stepper 8am→10am before/after + Reduce Motion note; B1/B2/B3 comparison on Mess around (scratch); one AX-size check frame (card + hero); foundations — `TimeIt/Card Float` effect style, dark `gradient/*` values, `TimeIt/Card Title` 17 Semibold.
- Wizard + settings: none now.
- Doc drift to record in §3 once verified live: `surface/card-elevated`.

Research note (the lead's one Sonnet helper): "dark mode elevates by lightness, not shadow" and the Reduce Transparency solid fallback are well supported; its specifics on Apple Weather's surfaces and Apple's stepper behaviour were unverified.
