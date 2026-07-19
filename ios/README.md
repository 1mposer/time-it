# ios/ — the native SwiftUI app

- **`TimeIt/`** — the app. SwiftUI/MVVM, iOS 17+, no third-party packages. Built per the #5a/#5b specs in [`docs/issues/`](../docs/issues/); shipped, live-verified, audited.
- **`guidelines/Guidelines.md`** — visual token truth for the **shipped (v1) light-only UI**. `Theme.swift` and the chip-tier tests pin against it.
- **`GLOSSARY.md`** — iOS design vocabulary for the wizard redesign (showcase card, range-first, diurnal/nocturnal…).

**UX source of truth for the next visual iteration** is the Figma file **Main - Time-it** (`t3ZRvcYPnSRPKElSLAFqmG`): full multi-page design system (Primitives/Semantic Light+Dark variables, component sheets, Light/Dark screen galleries incl. all 9 wizard frames), built 2026-07-18 per [`docs/design/figma_foundations_multi-page_implementation.md`](../docs/design/figma_foundations_multi-page_implementation.md).

The Figma Make React/Vite mockup that used to live here was deleted 2026-07-19 (its stated deletion condition — "once the SwiftUI app exists" — was met, and the Figma file now holds the runnable picture). Recover from git history if ever needed.
