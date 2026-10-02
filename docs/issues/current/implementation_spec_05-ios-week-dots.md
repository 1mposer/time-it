# Implementation spec 05 — iOS: week dots everywhere, today-only card, chevron collapse, detail day-jump

> **Status 2026-10-02: build order written; implementer dispatched.** Owner rulings 2026-10-02 (record: [FIGMA.md §11](../../design/FIGMA.md)); frames are the design truth, this spec is the build order. Mirrors the 2026-10-02 frames on both Screens pages: ring card `458:394` / `487:400`, dashboards `111:2` / `121:2` / `266:5` / `266:1562`, Activity Detail `456:358` … + `508:417` "Day jump — Thursday" (dark twins `491:*` / `509:836`). One `feat(ios):` commit, TestFlight-bound → bump `CURRENT_PROJECT_VERSION` 6 → 7 in the same commit.

## Rulings being built (owner, 2026-10-02)

1. **The week-dot row is the one way to show days** on every surface: seven dots in **forecast order from today** (dayIndex 0..6), a weekday initial over each, the dot coloured by that day's verdict, a blue ring on **today** (card) or on the **selected day** (detail). Figma component `517:73` "Week Dots" (Activity Card sheet) is the drawn truth.
2. **The card is today-only** — reverses the 2026-09-01 fall-forward (`DashboardViewModel.cardDayIndex` returning 1 when today's Range has passed). The card always shows `days[0]`; the week is visible in its dot row.
3. **Chevron, top-right of every dashboard card:** `chevron.down` while the dot row is shown (the natural state), `chevron.right` while hidden. Tap toggles. **Remembered per card across launches.**
4. **Detail day-jump:** the detail opens on today; the dot row under the nav is the jump control — tap a dot to show that day (ring moves, hero + stepper + metric cards re-read for that day; the stepper re-opens on that day's first Range hour).

## Code changes

### A. `WeekDots` — pure model + view (new files, `Services/WeekDots.swift` + `Views/WeekDotsView.swift`)
- `struct WeekDot: Equatable { let dayIndex: Int; let letter: String; let tier: WeekDotTier }`, `enum WeekDotTier { case perfect, good, bad, noData }`.
- `enum WeekDots { static func dots(for activity: ActivityRating, deriver: TimeDeriver, count: Int = 7) -> [WeekDot] }` — forecast order from day 0; `letter` = the weekday initial for that day in the **forecast's zone** (add `TimeDeriver.weekdayLetter(forDayIndex:)` — `EEEEE`, `en_US_POSIX`, same zone as the existing `weekdayFormatter`; derive the day's date from the bucket's first hour / day 0 + dayIndex days, consistent with `dayName(forDayIndex:)`). Tier: `rating == .perfect` → `.perfect`, `.good` → `.good`, `rating == nil` with a non-nil `score` → `.bad`, and `.noData` when the day is **absent from `days[]`** (a nocturnal activity has one fewer bucket) **or its `score` is `nil`** (the zero-hour bucket, ADR-0011 null rule). Unknown rating (`.unknown`) → `.bad` (never favourable on an unknown verdict — the 2026-08-29 hardening posture).
- `WeekDotsView(dots: [WeekDot], ringedDayIndex: Int?, onTap: ((Int) -> Void)? = nil, identifierPrefix: String)` — HStack of seven equal-width cells: letter (10pt, `Theme.secondaryText`; the ringed day's letter `Theme.primaryText`), then an 18pt slot holding the 10pt dot (`Theme.perfectGreen` / `Theme.accentOrange` / `Theme.badRed` / `.noData` = `Theme.timelineTrack` fill + 1pt `Theme.divider` stroke) and the 18pt ring (`Theme.accentInteractive`, 1.5pt) when ringed. `.noData` dots are **not tappable**. With `onTap`, each cell is a button with a ≥44pt tap target (the beta-pill ±padding pattern) and `accessibilityIdentifier("\(identifierPrefix).\(dayIndex)")`; the row carries `accessibilityIdentifier(identifierPrefix)`. Accessibility label per dot: "<Weekday>, <Perfect|Good|No window|No data>" (use `TimeDeriver.dayName(forDayIndex:)` so day 0 reads "Today"). Respect `accessibilityReduceMotion` for the ring move (easeOut 0.2 otherwise).

### B. Card — `ScoreRingCardView` + `DashboardView`
- `ScoreRingCardView` gains `weekDots: [WeekDot]` and `showsWeekDots: Bool`. When shown: the dots row sits **under the axis numerals, 8pt below**, aligned with the strip (x of the strip, strip width); the card's `detailColumn` fixed height grows accordingly (measure the frame: axis bottom → dots top 8pt; same bottom padding as today). When hidden: exactly today's card (no empty space). Animate the toggle with `.easeOut(0.2)` unless reduce-motion. `accessibilityIdentifier("weekDots.\(activityId)")` on the row.
- **Chevron:** drawn by the dashboard's existing top-trailing overlay, **right of the gear**: `HStack(spacing: 0) { gearButton; chevronButton }` where `chevronButton` = `Image(systemName: expanded ? "chevron.down" : "chevron.right")`, 13pt semibold, `Theme.secondaryText`, 34×34 frame + `contentShape` (the gear's pattern), `.buttonStyle(.borderless)`, `accessibilityIdentifier("cardChevron.\(activityId)")`, label "Hide week" / "Show week". The chevron is the right-most element (the ruling says top-right); the gear moves left of it. Grow `topRow`'s trailing padding so the chip never runs under either button. *(Judgment call recorded for the owner: the frames omit the gear; code keeps it, left of the chevron.)*
- **Today-only:** `DashboardViewModel.cardDayIndex(for:)` returns `0` always — delete the fall-forward branch and its comment; keep `rangeHasPassedToday` only if something else still calls it (grep; if nothing does, delete it with its tests). Update every test that pinned the fall-forward to pin today-only instead (a passed-Range today still shows `days[0]`).
- `DashboardView.card(for:authored:)` passes `weekDots: WeekDots.dots(for: activity, deriver: viewModel.timeDeriver)` (empty when no deriver) and `showsWeekDots: !preferences.collapsedCardIds.contains(authored.id)`.

### C. Persistence — `PreferencesStore`
- `static let collapsedCardsKey = "collapsedCards"`; `@Published var collapsedCardIds: Set<String>` (persisted through the existing `persist`/`load` helpers; default empty = every card expanded). `func toggleCardCollapsed(_ id: String)`.
- Add the key to the `UITEST_RESET` wipe list in `App/TimeItApp.swift`.
- Deleting an Activity removes its id from the set (hook where `ActivityStore` deletions are observed, or prune on load — pick the simplest; say which).

### D. Detail day-jump — `ActivityDetailView`
- `@State private var selectedDayIndex = 0`. Every `dayIndex: 0` in the view (`rawDay`, `rangeHourIndices`, `walkableHourRange`, the `today` property — rename to `selectedDay`) reads `selectedDayIndex`. `scoreAccessibilityLabel` follows.
- The dots row goes **under the nav bar, above the hero** (first child of the VStack, 365 wide = full content width, then the 12pt stack spacing — the frame shows 10pt dots→hero; keep the view's existing 12pt spacing and note the 2pt drift, or match 10: implementer's call, say which): `WeekDotsView(dots:, ringedDayIndex: selectedDayIndex, onTap: jump(to:), identifierPrefix: "detail.weekDot")`.
- `jump(to day:)`: guard the day exists and is not `.noData`; set `selectedDayIndex = day` and `selectedIndex = nil` (so `HourStepper.initialSelection` re-opens on that day's first Range hour — the frame's "a jump re-opens on 6am"); `stripPressed`/snap-back unchanged. Animate (easeOut 0.2 / reduce-motion aware).
- The hero's rating word + ring, the stepper label, pills and metric cards all re-read for the selected day with **no other change** — they already take `dayIndex` through the view model helpers.
- Nocturnal activities: the dots show one `.noData` tail dot (one fewer bucket); the jump guard covers it.

### E. Build number
`ios/TimeIt/TimeIt.xcodeproj/project.pbxproj`: `CURRENT_PROJECT_VERSION = 6` → `7` on the two app-target configurations (leave the test target's `1`).

## Tests (TDD against the frames; all green before the commit)

Unit (`TimeItTests`):
- `WeekDotsTests` (new): forecast order from day 0; letters from a fixture deriver (Asia/Dubai, the committed real fixture's `forecastStart`) incl. a day-0 that is not Monday; tier mapping for perfect / good / rating-null-with-score (→ `.bad`) / `score == nil` (→ `.noData`) / absent 7th day (nocturnal → `.noData`) / `.unknown` (→ `.bad`); exactly seven entries even for a 6-day nocturnal activity and for an 8-day diurnal one (the 8th day is dropped).
- `PreferencesStoreTests`: `collapsedCardIds` defaults empty; toggle persists and round-trips through a fresh store on the same `UserDefaults` suite; toggling twice restores.
- `DashboardViewModelTests` (or wherever the fall-forward is pinned today — `CardSublabelTests`/`RangeWindowTests`; grep `cardDayIndex`): a passed-Range today yields `dayIndex 0`; the old "falls forward to tomorrow" expectation is replaced, not deleted silently (name the new test for the ruling).
- `TimeDerivationTests`: `weekdayLetter(forDayIndex:)` for day 0 and day 6 across a month rollover in the fixture zone.
- `HourStepperTests` unchanged (the day-jump reuses `initialSelection`).

UI (`TimeItUITests`, hermetic mock):
- Extend `testCardV2ShowsScoreRingHoursOnlyChipAndNoWords`: the dots row `weekDots.<id>` exists and the chevron `cardChevron.<id>` exists.
- New `testCardChevronHidesTheWeekAndIsRememberedAcrossRelaunch`: tap the chevron → `weekDots.<id>` gone; relaunch (same `UITEST_*` args, **without** `UITEST_RESET`) → still gone; tap again → back.
- Extend `testDetailV3ShowsHeroStepperMetricCardsAndNoWeek` (rename: the detail now shows the dot row, not week bars): `detail.weekDot` row present; tap `detail.weekDot.2` → `detail.selectedHour` reads that day's first Range hour and `detail.score` label changes to that day's verdict/score from the mock fixture (pick a day whose score differs from day 0 in the mock); tap `detail.weekDot.0` → back to today.

## Docs in the same commit (ADR-0009 sweep)
- `ios/guidelines/Guidelines.md` card rules: the v2 card carries the week-dot row (forecast order, ring on today) + the chevron (down = shown, right = hidden, remembered per card); the card is **today-only** (the 2026-09-01 fall-forward is retired); the detail opens on today and jumps by the dots.
- `docs/design/FIGMA.md` §11 gate line: "mirrored to code 2026-10-02 (build 7)".
- `docs/issues/ROADMAP.md` item 16: the small iOS build **landed** (today-only card + week dots + chevron + day-jump; build 7); next: item 13.
- `docs/STATUS.md` NOW/NEXT lines accordingly.
- `CLAUDE.md` is server-side and needs no change unless you touch a contract (you must not — the wire is untouched).
- This spec's status line → "built 2026-10-02 — commit <hash>" (the auditor archives it to `completed/` after merge).

## Rules
- Worktree only; **no push**; one commit; message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Server untouched. Wire untouched. No new third-party code.
- Run the unit suite and the UI suite with `xcodebuild test` on an available simulator (`xcrun simctl list devices available` to pick one; the shared scheme is committed — see `ios/README.md`). Report the exact counts and the command used. If the UI suite cannot run on this machine, say so explicitly and report the unit count alone — never claim a run you did not do.
- Hand-derive every expected number in tests from the fixtures; never read it off the code's output.
- Final report: files changed; the pure-model decisions (tier mapping, `.noData` rules); the gear/chevron layout; test counts (unit + UI) with the command; the build number diff; commit hash; worktree path + branch.
