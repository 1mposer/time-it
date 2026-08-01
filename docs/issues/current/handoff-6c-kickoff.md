# Handoff — kick off Issue #6c (device registration + daily digest)

**To:** the implementing agent
**Date:** 2026-08-01
**From:** auditing agent (senior dev session)

#5c is closed and pushed; `main` at `433c055` is code/test/doc-consistent. For what's built and where things stand, read [`docs/STATUS.md`](../../STATUS.md) — this handoff doesn't repeat it.

## Your task

Implement **[#6c — device registration + daily digest](implement-spec-issue-6c-registration-and-digest.md)**. The spec is self-contained and was grilled on 2026-07-16; its **Decisions made** block is settled — do not relitigate any of it (empty-`[]` upsert validity, 60-min shared weather cache, local-6am digest, single replica, `apns2` seam, etc.).

Read order before writing code: `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md` → the #6c spec → [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md).

## Constraints that bit previous sessions — respect them

1. **Owner prerequisite gate.** APNs credentials (`.p8`, Key ID, Team ID, bundle `com.timeit.app`) and the Railway Postgres add-on are **owner actions**. If they aren't in place, build and test everything behind the DI seams (fake `db`, fake APNs client) and flag the manual steps in your handoff — don't stall, and don't fake the credentials.
2. **TDD, existing suite stays green.** Backend tests must pass throughout (`npm test`). New modules get DI-factory tests in the `createRatingRouter` style — no `require.cache` patching, no live provider calls in tests.
3. **Extractions are refactors, not forks.** `validateActivities()` and the error-envelope helper are pulled *out of* the rating path; the rating route's error messages, paths, and existing tests must stay byte-identical (spec §4 spells out the two audited conditions).
4. **Do not touch other agents' in-flight files.** The working tree may carry uncommitted edits to `ios/TimeIt/TimeIt.xcodeproj/project.pbxproj`, `TimeIt.xcscheme`, `Models/AuthoredActivity.swift`, and the untracked `handoff-weatherkit-provider-abstraction.md` — these belong to the WeatherKit agent. Never stage, commit, or edit them. Commit backend files by explicit path.
5. **Docs are part of done.** This project treats doc/code drift as a defect. When behavior changes (e.g. `/rating` gaining the shared weather cache), update `CLAUDE.md` / `STATUS.md` / spec cross-references in the same commit series — and only claim in docs what the code actually does.
6. **Time handling:** the digest's local-day logic must go through `src/weather/timeBoundary.js` (`localDay` etc.) — do not hand-roll `Intl` calls.

## Done means

- `PUT`/`DELETE /api/v1/devices/:deviceId` per spec §4, Postgres schema per §3, weather cache per §6 (shared by jobs, upsert, **and** `/rating`), digest job per §7 — all with tests.
- `GET /health` still DB-independent; suite green; docs reconciled.
- A handoff for the auditor: what you built, what you claim, and which manual Railway/APNs steps remain for the owner. Claims will be independently verified — write only what you've run.
