# Handoff — depth & polish pass (ROADMAP item 17, build 8), updated 2026-11-05

> For the next session's agent. Role to inherit: **auditor / orchestrator** — the owner (Yaas, they/them) decides; Opus 5.5 agents implement in worktrees; Sonnet verifiers run both suites and screenshot; you read the diffs, merge, and bring the owner decisions as short multiple-choice questions, one at a time. Read order: `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md` → this file. Figma history and every design ruling of record: [FIGMA.md §12](../../design/FIGMA.md) (do not restate it here).

## Adversarial review — ran 2026-11-05, fix slice merged

- **How it ran:** Opus reviewed `git diff 0ca6fa3..0d79fe4 -- ios/TimeIt` blind (no handoff), then reconciled against this file; all ten findings kept, none dropped. Release build clean, suites green on the tip. Rulings page: https://claude.ai/artifact/4VB1SnRjNz5FGSu44HETUx — owner ruled **1a 2a 3a 4a 5b 6c 7a 8b 9b 10a** the same day.
- **Fixed now (a) — merged `1f1af06` (commit `356c088`), Sonnet-verified 552 unit / 41 UI + Release build:** (1) `SpanKey` carries the authored `ActivityInput`, so a thresholds-only edit clears the span score; (2) iOS 18+ pull gains an accessibility action "Refresh" (VoiceOver / Switch Control); (3) a failed pull over a live list keeps the cards (`keepsListOnFailure`), first-load errors unchanged — two unit pins; (4) the pull UI test now proves a refetch via the DEBUG-only `uitest.fetchCount` probe (`UITestFetchCounter`; launch fetches twice — first load, then the location fix's reload — so the test waits for 2, then expects 3); (7) the pull commits at the haptic — release refreshes iff armed, `PullRefresh.disarmFraction = 0.8` hysteresis, `PullRefresh.armed(wasArmed:overscroll:)` pinned; (10) `reduceMotion` captured outside the Sendable `scrollTransition` closure (warning gone), `LiftOnRelease` keyed on `trigger` alone with identity keyframes under Reduce Motion.
- **After TestFlight (b) — build 9, listed in the ROADMAP deferral table:** (5) passed hours / "Time passed" only update when the body re-renders (no minute tick on the card list or detail hero — only the header's `TimelineView` ticks); (8) `DashboardViewModel.timeDeriver` is a computed property allocating four formatters, recomputed many times per carousel scroll step — cache per forecast, profile on device first; (9) `programmaticSlot` can stay set after an interrupted `scroll(to:)` and swallow one selection haptic.
- **Accepted (c):** (6) below iOS 18 the system `.refreshable` inset probably keeps the card stagger spread for the whole refresh — reasoned only, no iOS 17 runtime here.
- **Observation, not ruled:** every launch fetches the forecast twice (first load, then the reload after the location fix) — one avoidable server call per launch; worth a look when item 13 touches launch.
- **Known and accepted, do not re-raise:** the wizard's Did-you-know ✕ cannot animate inside a SwiftUI `Form` (two attempts, reverted); the pushed detail must never use `@Environment(\.dismiss)` (XCUI hang) — it pops via the dashboard's `navigationPath`; no client-side score formula exists on purpose (ADR-0007 mirror #4 deleted); the June-2026 test fixture date plus a real clock makes mock runs show grey pills unless `UITEST_NOW` is pinned (the launch helper pins it); finding 6 above.
- **Suites** (from `ios/TimeIt`, simulator `31A62955-52C5-4208-9D53-2FF4ED8A705B`, one at a time, `pgrep -fl xcodebuild` empty first):
  `xcodebuild test -project TimeIt.xcodeproj -scheme TimeIt -destination 'id=<udid>' -derivedDataPath <scratch>/dd -only-testing:TimeItTests` then `-only-testing:TimeItUITests`. Attachments: `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` (manifest.json maps UUID → name). Pre-existing Debug warnings (not ours to fix now): main-actor ones in `MockRatingService.swift:69` and `PreviewFixtures.swift`.

## Where things stand (2026-11-05)

- **Build 8 code is complete and pushed:** `main` = `owner-tweaks` = `origin/main` = `4465d43` (pushed 2026-11-10 on the owner's word). `CURRENT_PROJECT_VERSION` = 8 (`767b104`). Any further code commit for build 8 is pushed only when the owner says so again.
- Last green: **552 unit / 41 UI** (review fix slice, 2026-11-05).
- Build 7 (`0ca6fa3`) is the last shipped code; the owner audited it live 2026-10-06 and ruled the depth pass; Figma rounds 1–3 + an edit loop followed (record: FIGMA.md §12). Coding ran 2026-11-03 → 11-05 on `owner-tweaks`, merging into `main` locally since 11-04.
- Process rule learned 2026-11-04: never run two suites on one simulator at once (runner kills, false failures).
- Owner approvals so far: carousel, motion, gone-hours, refresh, ring-64 and fade slices ("the current changes are approved", 2026-11-04); the 2026-11-05 mini edits were watched on the simulator as they landed.

## Shipped in build 8 (one line each; details in the commits)

- Detail hero carousel: Range as a snapping horizontal scroll, − / + pieces, grey gone hours, metric cards average the shown hours live (`469fbae`…`10bcdeb`).
- Band melt (fade) from the Final frames, static under Reduce Motion (`0eeebc1`).
- Hero wording: "Your range 6 – 10am · Time passed"; "No Window" in `noWindowTint` (`4caaf8a`).
- Span scoring: glass "Score 7 – 11am" capsule → "Scored 7 – 11am"; one server call, window swapped for the span; the Range line never changes (`33305d1`, `2f6a26a`).
- Edit circles: two 44pt captioned glass circles replace the edit list card; Delete lives in the detail's editor (`9ecd1b8`).
- UI-test clock pin `UITEST_NOW` (`9aba766`); appearance pin `UITEST_APPEARANCE`.
- Dark mode: dynamic tokens from Semantic Dark, Card Lift Dark, dark previews (`a702255`).
- Glass controls: `Glass.swift` vocabulary; header gear, Add Activity, Send a suggestion / Enable Location / Try Again as glass; **card gear removed** (`64462c8`).
- Header numeral swap: temperature is the 60 Light numeral, the clock leads the meta row (`0eeeabe`; owner re-confirmed 2026-11-05 after asking why).
- Dynamic Type: Figma-size scaling, AX stacking, single-column grid (`f4d5323`, `735db1b`).
- Mini edits round 1 (`745880c`, `bedb553`): clear-glass gear (`GlassStyle.clear`), pull-down stagger through the rubber band (k 0.35, fifth card ~1.5× the first), de-reveal on the callout ✕ / card chevron (0.35s no-bounce spring, `PressStyle` on the controls), Add capsule 40pt inside a 44pt target.
- Mini edits round 2 (`9edbf8e`): pull-to-refresh fires later — custom 110pt threshold on iOS 18+ with the Apple spinner revealed by the pull and a light haptic at the threshold; `.refreshable` kept below iOS 18. Rhythm tries (wider header gaps, 12pt card gap, 17pt meta row) were walked back the same day; the values stay as `Theme.Spacing` tokens at the original numbers.
- Adversarial-review fix slice (`356c088`, merged `1f1af06`): see the section above — six findings fixed, pull commits at the haptic, VoiceOver refresh, failed pull keeps the list, honest pull test, stale span score cleared, Reduce Motion lift fix.

## Remaining order (owner-gated where marked)

1. ~~Adversarial review~~ done (above).
2. ~~Push~~ done 2026-11-10. **NEXT:** Owner uploads to TestFlight from Xcode → ask what build number App Store Connect assigned and sync `project.pbxproj` the same session.
3. **Figma graduation** after the owner accepts build 8 on the simulator: redraw both themes to match the shipped code on the Screens pages (the Mess around scratch rows are behind the code on hero wording, colour, placement, the span capsule, the circles, glass, the meta row); clean the stale raw `0,0,0` numeral fills on S1/S2/S4/S5. Then ROADMAP 17 → built, STATUS, FIGMA.md §12 gate — one docs commit.
4. Item 13 (onboarding v2) on the new card.

## Open owner calls (by eye, none blocks TestFlight)

- Wizard tip ✕ snaps (Form limitation) — accept, or move the tip out of the Form later.
- Clock keeps AM/PM (locale formatter; Figma's "9:41" is a placeholder).
- Dark melt blob ships at 100% (the Figma node's value; its layer name says 45%).
- Fade end at the first card vs carried lower; the ring-tap return (an invention).
- AX sizes: the large "Score" caption narrows the card's name column; the Range line shrinks to 70% between xxxLarge and AX1.
- Still open from the build 7 review: the editor's review pills preview tomorrow under a "Today" label (FIGMA.md §11 (b)).
- Figma-side only: whether the dark chosen-pill numeral becomes a `text/on-rating` token.

## Standing rules (owner-adopted; do not relitigate)

- Owner communication: short plain English, action list first; decisions one at a time as multiple choice, or one artifact page with a/b/c options. Call a mock surface a "screen".
- No code push unless the owner says so. Docs-only batches under `docs/` commit without asking (after the 2026-11-10 push they go straight to `origin/main` again).
- Status/gate changes sweep ROADMAP + STATUS (+ FIGMA.md) in one commit. Figma inventory claims only from a live enumerate.
- Implementers: `model: "opus"`, worktree isolation, `git reset --hard <base>` first; Sonnet verifier re-runs both suites alone; merge `--no-ff` into `main`, `--ff-only` into `owner-tweaks`, remove the worktree. Never perform a subagent's denied action in its place.
- Orchestrator stays hands-off on Figma and suites (owner rule 2026-10-30) — **except** when the owner says "do it yourself, no need to spawn someone" (2026-11-05: direct Theme edits + build + install + unit runs were owner-authorised for quick visual tunes).
- Attribution: commits end with the lines the harness provides.

## Suggested skills

`1mposer-skills:apple-fluid-motion` + `phone-gestures` (any motion change — the owner names these) · `apple-hig` (project skill) · `figma:figma-use` before any `use_figma` call (`get_metadata` is broken for this file) · `artifact-design` (owner pages).

## Simulator notes

- iPhone 17e `31A62955-52C5-4208-9D53-2FF4ED8A705B`, iOS 26.5, Xcode 26.6. Opening the Simulator app may select another device — pass `--args -CurrentDeviceUDID <udid>` and `xcrun simctl launch <udid> com.timeit.app.dev`.
- A plain launch hits the real backend with the real clock (passed Ranges render grey — by design). Screenshots: `xcrun simctl io <udid> screenshot` (px = pt × 3).
- Stand-in backend if needed: `express` + `createRatingRouter({ getWeather: async () => fakeWeather() })` with hours tagged by `timeBoundary.tagLocalDays`, `PUT/DELETE /api/v1/devices/:id` and `POST /api/v1/feedback` → 204, on `127.0.0.1:3000` (Debug `APIConfig.baseURL`); ~80 lines to recreate.
