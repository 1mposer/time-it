# ios/ — the native SwiftUI app

- **`TimeIt/`** — the app. SwiftUI/MVVM, iOS 17+, no third-party packages. Built per the #5a/#5b/#5c specs in [`docs/issues/completed/`](../docs/issues/completed/) (historical records; build status: [ROADMAP](../docs/issues/ROADMAP.md)). #5c made location worldwide: Dubai fallback deleted, Active-location chain, MapKit city picker.
- **Tooling facts:** the Xcode project is hand-written (Xcode 16 synchronized-folder format, no xcodegen); the shared scheme is committed on purpose (`xcodebuild test` needs it). The XCUI suite is hermetic — DEBUG-only `MockRatingService` behind `UITEST_MOCK_SUCCESS`/`UITEST_MOCK_FAILURE`, `UITEST_RESET` wipes persisted state, location args `UITEST_LOCATION`/`UITEST_LOCATION_DENIED`; the repo carries no `.env`/API key. The decoder is pinned by a committed real 166-hour night-spanning response fixture.
- **`guidelines/Guidelines.md`** — behavioral + iconography guide for the shipped (v1) light-only UI (chip tiers pinned by `MetricColorTests`, card rules, SF-Symbols manifest). Token *values*: `Theme.swift` (shipped truth) + the Figma file (design truth — [FIGMA.md](../docs/design/FIGMA.md), ADR-0009).
- **`GLOSSARY.md`** — iOS design vocabulary for the wizard redesign (showcase card, range-first, diurnal/nocturnal…).

**Figma is the UI source of truth — frames precede code ([ADR-0008](../docs/adr/0008-figma-first-ui-gate.md)).** The file **Main - Time it** (`t3ZRvcYPnSRPKElSLAFqmG`) holds the full multi-page design system. Access, page map, tokens, and workflow: [`docs/design/FIGMA.md`](../docs/design/FIGMA.md).

The Figma Make React/Vite mockup that used to live here was deleted 2026-07-19 (its stated deletion condition — "once the SwiftUI app exists" — was met, and the Figma file now holds the runnable picture). Recover from git history if ever needed.
