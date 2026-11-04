# Handoff — depth & polish pass (ROADMAP item 17), written 2026-10-06, updated 2026-11-04

> For the next session's agent. Role to inherit: **auditor / orchestrator** — the owner (Yaas) decides, Opus 5.5 agents implement in isolation, you verify everything they claim (live Figma enumerate + screenshots, both test suites) and bring the owner one decisions page per round. Read order first: `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md` → `docs/issues/ROADMAP.md` item 17 → `docs/design/FIGMA.md` §1, §3, §6, §11, **§12** → the [design-lead report](design-lead-report-depth-pass-2026-10-06.md).

## Where things stand

- **main** carries build 7 (`0ca6fa3`) + the docs commits through 2026-10-30; build 7 is the last shipped code.
- Build 7 was walked live on the iPhone 17 simulator against a stand-in backend (real `createRatingRouter` fed fake weather; no API key, no Postgres) — walkthrough page https://claude.ai/artifact/Qrc9CgEvWX8F3e6vCUfDSQ. The owner's audit followed; an Opus design lead produced the report above; the owner ruled **"all a"** on https://claude.ai/artifact/69h798izJuJ4hLE8bBcdCP with ruling 2 amended (**no long press — tap opens the detail; editing only from the detail's rows**). Rulings of record: FIGMA.md §12.
- **Drawn on Mess around, not graduated; coding started 2026-11-03 on `owner-tweaks` (local, unpushed, base `0677ae9`).** Nothing is on the Screens pages. ADR-0008 gate: coding started 2026-11-03 on `owner-tweaks` (local, unpushed) from the ruled behaviour; Final – Opus v1 superseded for the pill look; remaining Figma-only items are the ones listed under "Remaining order" below. The approval page was not ruled on as drawn — the owner rejected the Final's pill size ("return the old bars, keep + and − at the ends"). Gate record: FIGMA.md §12.
- Still open from the build 7 review (not in item 17): the editor's review pills preview tomorrow under a "Today" label (FIGMA.md §11, question (b)).
- Order **owner-confirmed 2026-10-06**: item 17 before item 13 (the card and detail it changes sit on onboarding 06/07).
- Housekeeping done 2026-10-06: spec 03 archived to `docs/issues/completed/` (owner-authorized).

## The agent flow ahead (in order)

1. **Owner pre-check — DONE 2026-10-06:** the earlier "no edit access" was a case typo in the fileKey (lowercase `r`; the key is `t3ZRvcYPnSRPKElSLAFqmG`, FIGMA.md §1). With the key of record, `whoami`, a read, and a reversible write probe on Mess around all succeeded. Both of the lead's claims verified and recorded in FIGMA.md §3/§12.
2. **Round 1 drawing pass — DONE 2026-10-06** (Opus implementer, Mess around `179:5` scratch): record + every node ID in FIGMA.md §12. Rules it followed: clone/instance, never redraw; bind `Semantic`, radii `Layout`, text `TimeIt/*`; ≤10 ops per call; return every node id; never touch nodes outside the order; stop on any denied delete and report.
3. **Owner ruling on round 1 — DONE 2026-10-30** (page https://claude.ai/artifact/6Ryubfn3tpmjurPZt53w6q): card, Passed card, AX approved; hero, stepper, fade, temp weight, dark greys sent back. Record: FIGMA.md §12.
4. **Round 2 drawing pass + Sonnet verification — DONE 2026-10-30** (Mobbin-informed fade — research: [mobbin-fade-references-2026-10-30](../../research/mobbin-fade-references-2026-10-30.md)); record: FIGMA.md §12.
5. **Owner decisions page 2 — DONE, ruled 2026-10-31** (page https://claude.ai/artifact/V2kwTahW7d5a32T984nX9F; rulings: FIGMA.md §12).
5b. **Round 3 drawing pass + Sonnet verification — DONE 2026-10-31** (Mess around, third scratch row; record: FIGMA.md §12). 
5c. **Owner rulings on decisions page 3 — DONE 2026-11-01** (page https://claude.ai/artifact/Ch8i4i8D1ZjdaSsLf4UbHg; rulings: FIGMA.md §12).
5d. **Edit loop — DONE 2026-11-01** on Mess around's fourth scratch row (record: FIGMA.md §12). The owner did not rule on its approval page as drawn; see step 7.
6. **Graduate to the Screens pages** — only after the code is owner-accepted on the simulator (light + dark twins, the frame list in report §6; 06/07 by re-instancing the card). Update FIGMA.md §12 gate state, ROADMAP 17, STATUS in one docs commit (docs-only batches auto-commit + push). Carry the cleanup: the round-3 numeral fills on S1/S2/S4/S5 hold a stale raw 0,0,0 under their `text/primary` binding — clean on graduation. NOT STARTED.
7. **iOS depth pass (build 8) — IN CODE on `owner-tweaks` since 2026-11-03** (no separate spec 06 was written; the owner's rulings drove the build). Process: Opus implementer in a worktree, an independent Sonnet verifier runs both suites, the orchestrator merges fast-forward into `owner-tweaks`; the global `edit-loop` skill was used for the Figma round only. Commits `469fbae`, `18ccacf`, `4b37a22`, `e4d380a`, `d692dcc`, `bf8c6db`, `10bcdeb`. Last green (Sonnet suite runs): 458 unit / 35 UI.
   - **Shipped:**
     - Detail hero carousel: the chosen span (Range length) slides as a native horizontal scroll with snap; − / + are two pieces flanking the row; one spare slot either side at rest; pills shrink so long Ranges always fit; ended hours draw grey. Metric cards average the chosen hours LIVE — no Calculate button (the owner reversed the 2026-10-31 "press to calculate" ruling on 2026-11-03, judging the button non-intuitive). One line under the row reads "Your range …" on the Range, or "Showing …" plus an icon return button when away; tapping the score ring is a second way home. The score ring and rating word never change with the span.
     - Gone hours: the dashboard card strip and the detail row both always draw the full authored Range; hours before the forecast start (or ended) render grey with no weather (`HourSlot`); averages use data hours only (owner ruling 2026-11-04, replacing the data-only strip).
     - Dashboard pull-down stagger (gaps open progressively, the last card fastest; the owner tuned the strength) and pull-to-refresh.
     - Hero spacing from the Figma Layout tokens (space xs/sm/md/lg/xl, radius sm/md/lg/full) as named constants in `Theme.swift`; score ring 64pt (owner ruling 2026-11-04, down from the Figma 80).
     - Liquid Glass on the − / + pieces, gated to iOS 26 (owner experiment).
   - **In progress (2026-11-04):** the dashboard band melt (fade) from the Final frames `839:3930` / `839:4160`, blob inside the mask, drift 20–40 s, off under Reduce Motion; the fade end is kept at the first card (+111) as one constant pending the owner's call.
   - **Remaining order for build 8:** fade (in progress) → hero wording "Time passed" / "No Window" in regular grey, no jump line → dark tokens (Dark `gradient/*`, `timeline/track` gray/700, Card Lift Dark) → header numeral swap with scrim → Dynamic Type pass on the detail (fonts are fixed sizes today) → bump `CURRENT_PROJECT_VERSION` 7 → 8 in the integration commit → owner decides on a Fable adversarial review → push + TestFlight → ask the owner for the App Store Connect build number.
   - **Open owner calls:** (1) fade end at the first card vs carried lower; (2) whether the dark chosen-pill numeral colour becomes a `text/on-rating` token (Figma-side); (3) close the superseded Figma approval page, and graduate frames only after simulator acceptance; (4) the ring-tap return is an invention to judge on the simulator.
8. **Implementer, Opus, worktree isolation**, TDD against the spec. A Sonnet verifier re-runs both suites from `ios/TimeIt`:
   `xcodebuild test -project TimeIt.xcodeproj -scheme TimeIt -destination 'id=<sim udid>' -derivedDataPath <scratchpad>/dd -only-testing:TimeItTests` (then `TimeItUITests`). (Last green on `owner-tweaks`: see step 7.) Ask the owner whether a Fable adversarial review runs before merge (they waived it on 2026-10-02).
9. Merge to main, docs sweep (ROADMAP 17 → built, STATUS, FIGMA.md §12 "mirrored to code"), **no push unless the owner says so**; after the owner uploads, ask what build number App Store Connect assigned and sync `project.pbxproj`. NOT STARTED.
10. Then **item 13** (onboarding v2 build) on the new card.

## Standing rules (owner-adopted; do not relitigate)

- Owner communication: short plain English, action list first; decisions as one artifact page with a/b/c options — the first long-form page was rejected as "far too verbose".
- No code push unless the owner says so; docs-only batches under `docs/` auto-commit + push. Commits end with the attribution lines the harness provides (do not hardcode a model name).
- Status/gate changes sweep ROADMAP + STATUS (+ FIGMA.md) in one commit. Figma inventory claims only from a live enumerate. Never perform a subagent's denied action in its place. Destructive actions get owner confirmation.
- Implementers: `model: "opus"`, worktree isolation for code; design/draw agents may spawn at most one Sonnet research helper (owner grant 2026-10-06).
- **Orchestrator stays hands-off (owner rule 2026-10-30):** never run `use_figma` / screenshots / `xcodebuild` yourself — spawn a Sonnet verifier for every audit (enumerate, screenshot, suites) and judge its report. Mirrored in CLAUDE.md agent workflow rules.
- **Mobbin MCP** (added by the owner 2026-10-30) is connected and the fade research is done — findings persisted in [`docs/research/mobbin-fade-references-2026-10-30.md`](../../research/mobbin-fade-references-2026-10-30.md) (the earlier 403 from mobbin.com is history).

## Suggested skills

`figma:figma-use` (before any `use_figma` call; `get_metadata` is broken for this file; one `setCurrentPageAsync` per call) · `apple-hig` (project skill, `.claude/skills/apple-hig`) · `design-lead` (`~/.claude/skills/design-lead`, for any new thin brief) · `frontend-design` (plugin) · `artifact-design` (owner pages).

## Simulator + stand-in backend (if a live walk is needed again)

- Stand-in server pattern: `express` + `createRatingRouter({ getWeather: async () => fakeWeather() })` with hours tagged by `src/weather/timeBoundary.tagLocalDays`; `PUT/DELETE /api/v1/devices/:id` and `POST /api/v1/feedback` → 204; listen `127.0.0.1:3000` (Debug `APIConfig.baseURL`). The 2026-10-06 copy lived in the session scratchpad (`walk/fake-server.js`) and may be gone — it is ~80 lines to recreate.
- Driving the simulator: a CGEvent tap tool needs Simulator frontmost (`osascript -e 'tell application "Simulator" to activate'`); with `defaults write com.apple.iphonesimulator ShowChrome -bool false` the window equals the device screen at 100%; screenshots via `xcrun simctl io <udid> screenshot` (px = pt × 3). Restore chrome: `defaults delete com.apple.iphonesimulator ShowChrome`.
- A `node fake-server.js` on :3000 may still be running from 2026-10-06; kill it if port 3000 is busy.
