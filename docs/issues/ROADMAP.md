# Roadmap

## Build order

**#5a and #5b are built; next: #6b → #5c → #6c → #6d (grilled + re-specced 2026-07-16, [ADR-0006](../adr/0006-device-keyed-push-evaluation.md)). Compact between each sub-issue. #7 and #8 can be done any time after #4.**

## Critical path

- [#3 Backend Internals](completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — ✅ merged
- [#4 HTTP API](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — ✅ merged
- [#10 Pre-5a hardening](completed/implement-spec-issue-10-hardening.md) ([GitHub](https://github.com/1mposer/time-it/issues/10)) — ✅ complete — typed `UpstreamError`, null-safe Meteosource adapter, DI factory router, `forecastStart` `Z` suffix, expanded test coverage (8 test files)
- [#5a Core iOS app](completed/implement-spec-issue-5a-ios-core.md) — ✅ **built, live-verified, audited + merged to `main` (2026-07-12)** (read-only dashboard; no accounts per [ADR-0001](../adr/0001-no-accounts-guest-first.md)). Current state: [STATUS §5](../STATUS.md).
- [#5b Personalization layer](completed/implement-spec-issue-5b-ios-personalization.md) — ✅ **built (2026-07-13, TDD) + independently re-reviewed 2026-07-15, all findings fixed** (client-side activity authoring + local persistence; Pro/StoreKit deferred). Current state: [STATUS §5](../STATUS.md).
- Shared: [design-decisions-issue-5.md](current/design-decisions-issue-5.md) · [ios/guidelines/Guidelines.md](../../ios/guidelines/Guidelines.md)
- #6a Backend infrastructure — **CUT ([ADR-0001](../adr/0001-no-accounts-guest-first.md))**: accounts/auth removed; user prefs are client-side (#5b)
- [#6b Railway deployment](current/implement-spec-issue-6b-railway-deploy.md) — **deployed + live-verified 2026-07-20** (`https://time-it-production.up.railway.app`; health/POST/400 probes green, Serverless off, Release URL wired into `APIConfig.swift`); remaining: Release build on a real device
- [#5c Location onboarding](current/implement-spec-issue-5c-location-onboarding.md) — worldwide launch posture: **Dubai fallback deleted**, grayed empty state + "Enable location" / "Place your own location" (MapKit city search); soft prerequisite of #6c (registration needs a real location)
- [#6c Device registration + daily digest](current/implement-spec-issue-6c-registration-and-digest.md) — Postgres, snapshot upsert (`PUT /api/v1/devices/:deviceId`), `apns2` seam, per-device local-6am digest ([ADR-0006](../adr/0006-device-keyed-push-evaluation.md))
- [#6d Perfect-window detector](current/implement-spec-issue-6d-perfect-window-detector.md) — hourly, Perfect-only, once per (device, activity, bucket), buckets 0–1
- **UX evolution (post-#6d)** — the range-first authoring wizard: every Activity is a user-placed daily time range ("check every day, from X to Y"); design pinned **2026-07-20** in Figma **"Main - Time it"** (wizard mind-map page; the "SwiftUI as-built" page mirrors the current build). Companion decision already landed: card = day 0 only ([ADR-0004 amendment 2026-07-20](../adr/0004-day-bucketed-rating-wire-shape.md)). Range is mandatory **in the UI only** — the wire `window` stays optional (ADR-0005 untouched); ranges are whole-hour; the wizard must make `From == To` unpickable and derive the duration cue (wrap-aware: `22→2` = 4h, and a wrap = nocturnal). Spec deliberately unwritten until the #6 wave completes.

## Parallel tracks (open now)

- [#7 Marine Data](current/implement-spec-issue-7-marine-data.md) ([GitHub](https://github.com/1mposer/time-it/issues/7)) — investigate Meteosource API tier before writing any code
- [#8 requireTrue threshold](current/implement-spec-issue-8-require-true-threshold.md) ([GitHub](https://github.com/1mposer/time-it/issues/8)) — small engine change, unblocks future stargazing features. **Scope grew (2026-07-15 review finding):** `validateRatingRequest` must also check a threshold's *shape* against its metric's *kind* — today a `type:"flag"` threshold on a numeric metric passes validation and then never fails an hour (silent false-Perfect); needs kind awareness in `metricCatalog.js` (the iOS mirror already rejects it)

## Notes

- Sub-issue specs live in the local spec files above — **the tree is the source of truth** (the #5 and #6 GitHub issues were removed).
- The old single-file #6 spec was superseded and deleted 2026-07-16 (git history keeps it); its decisions live in [ADR-0006](../adr/0006-device-keyed-push-evaluation.md) + the four spec files above.
- #6c requires an Apple Developer account ($99/year) + APNs `.p8` key — prerequisite before starting that sub-issue (see its header).
- When an issue is fully merged, move its spec to `docs/issues/completed/`.
