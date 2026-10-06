# Handoff — depth & polish pass (ROADMAP item 17), written 2026-10-06

> For the next session's agent. Role to inherit: **auditor / orchestrator** — the owner (Yaas) decides, Opus 5.5 agents implement in isolation, you verify everything they claim (live Figma enumerate + screenshots, both test suites) and bring the owner one decisions page per round. Read order first: `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md` → `docs/issues/ROADMAP.md` item 17 → `docs/design/FIGMA.md` §1, §3, §6, §11, **§12** → the [design-lead report](design-lead-report-depth-pass-2026-10-06.md).

## Where things stand

- **main** carries build 7 (`0ca6fa3`) + the docs commits of 2026-10-06; pushed as the owner's checkpoint. Working tree clean.
- Build 7 was walked live on the iPhone 17 simulator against a stand-in backend (real `createRatingRouter` fed fake weather; no API key, no Postgres) — walkthrough page https://claude.ai/artifact/Qrc9CgEvWX8F3e6vCUfDSQ. The owner's audit followed; an Opus design lead produced the report above; the owner ruled **"all a"** on https://claude.ai/artifact/69h798izJuJ4hLE8bBcdCP with ruling 2 amended (**no long press — tap opens the detail; editing only from the detail's rows**). Rulings of record: FIGMA.md §12.
- **Nothing is drawn or coded yet.** ADR-0008 applies: frames precede code.
- Still open from the build 7 review (not in item 17): the editor's review pills preview tomorrow under a "Today" label (FIGMA.md §11, question (b)).
- Order **owner-confirmed 2026-10-06**: item 17 before item 13 (the card and detail it changes sit on onboarding 06/07).
- Housekeeping done 2026-10-06: spec 03 archived to `docs/issues/completed/` (owner-authorized).

## The agent flow ahead (in order)

1. **Owner pre-check — DONE 2026-10-06 (second session):** the earlier "no edit access" was a case typo in the fileKey (lowercase `r`; the key is `t3ZRvcYPnSRPKElSLAFqmG`, FIGMA.md §1). With the key of record, `whoami` (Full seat, Pro team), a read, and a reversible write probe on Mess around all succeeded. Both of the lead's claims verified and recorded in FIGMA.md §3/§12: `Semantic` has `surface/card-elevated` (`VariableID:91:208`); one effect style `TimeIt/Card Shadow` exists.
2. **Drawing pass, Opus implementer** (`model: "opus"`, read-only on the repo, Figma write): work order from the report §6 + FIGMA.md §12. Scratch on **Mess around `179:5`** first: the B1 card (no gear), Passed A1/A2, detail C1/C2, stepper D1 before/after, the dashboard with the ground fade + temperature numeral (F), one AX-size check frame, the `TimeIt/Card Float` effect style, dark `gradient/*` values, `TimeIt/Card Title` 17. Rules: clone/instance, never redraw; bind `Semantic`, radii `Layout`, text `TimeIt/*`; ≤10 ops per call; return every node id; never touch nodes outside the order; stop on any denied delete and report. Auditor re-enumerates and screenshots everything claimed.
3. **Owner decisions page** (one artifact: a screenshot per frame, one-line ask each, priority order). Approve / tweak.
4. **Graduate to the Screens pages** on the owner's tick (light + dark twins, the frame list in report §6; 06/07 by re-instancing the card). Update FIGMA.md §12 gate state, ROADMAP 17, STATUS in one docs commit (docs-only batches auto-commit + push).
5. **Spec 06 — iOS depth pass (build 8)**: written by you from the approved frames + the report. Must cover: the day cache (key/value/invalidation, no indices stored), the vocabulary table, the hero fix at the call site (never `Theme.ratingTint`), the stepper (concatenated `Text` keeps `detail.selectedHour`; explicit Reduce Motion gate), the shared float shadow replacing six copies, the ground fade geometry, the header numeral swap, Dynamic Type on card/hero/stepper (text styles + intrinsic heights replace the fixed 65/107 column), and the UI tests to touch (seven `gear.*` steps go; `score.*` strings unchanged unless VoiceOver copy changes). Bump `CURRENT_PROJECT_VERSION` 7 → 8 in the same build.
6. **Implementer, Opus, worktree isolation**, TDD against the spec. Auditor re-runs both suites from `ios/TimeIt`:
   `xcodebuild test -project TimeIt.xcodeproj -scheme TimeIt -destination 'id=<sim udid>' -derivedDataPath <scratchpad>/dd -only-testing:TimeItTests` (then `TimeItUITests`). Last green: 413 unit / 33 UI. Ask the owner whether a Fable adversarial review runs before merge (they waived it on 2026-10-02).
7. Merge to main, docs sweep (ROADMAP 17 → built, STATUS, FIGMA.md §12 "mirrored to code"), **no push unless the owner says so**; after the owner uploads, ask what build number App Store Connect assigned and sync `project.pbxproj`.
8. Then **item 13** (onboarding v2 build) on the new card.

## Standing rules (owner-adopted; do not relitigate)

- Owner communication: short plain English, action list first; decisions as one artifact page with a/b/c options — the first long-form page was rejected as "far too verbose".
- No code push unless the owner says so; docs-only batches under `docs/` auto-commit + push. Commits end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Status/gate changes sweep ROADMAP + STATUS (+ FIGMA.md) in one commit. Figma inventory claims only from a live enumerate. Never perform a subagent's denied action in its place. Destructive actions get owner confirmation.
- Implementers: `model: "opus"`, worktree isolation for code; design/draw agents may spawn at most one Sonnet research helper (owner grant 2026-10-06).

## Suggested skills

`figma:figma-use` (before any `use_figma` call; `get_metadata` is broken for this file; one `setCurrentPageAsync` per call) · `apple-hig` (project skill, `.claude/skills/apple-hig`) · `design-lead` (`~/.claude/skills/design-lead`, for any new thin brief) · `frontend-design` (plugin) · `artifact-design` (owner pages).

## Simulator + stand-in backend (if a live walk is needed again)

- Stand-in server pattern: `express` + `createRatingRouter({ getWeather: async () => fakeWeather() })` with hours tagged by `src/weather/timeBoundary.tagLocalDays`; `PUT/DELETE /api/v1/devices/:id` and `POST /api/v1/feedback` → 204; listen `127.0.0.1:3000` (Debug `APIConfig.baseURL`). The 2026-10-06 copy lived in the session scratchpad (`walk/fake-server.js`) and may be gone — it is ~80 lines to recreate.
- Driving the simulator: a CGEvent tap tool needs Simulator frontmost (`osascript -e 'tell application "Simulator" to activate'`); with `defaults write com.apple.iphonesimulator ShowChrome -bool false` the window equals the device screen at 100%; screenshots via `xcrun simctl io <udid> screenshot` (px = pt × 3). Restore chrome: `defaults delete com.apple.iphonesimulator ShowChrome`.
- A `node fake-server.js` on :3000 may still be running from 2026-10-06; kill it if port 3000 is busy.
