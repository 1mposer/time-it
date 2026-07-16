# Roadmap

## Build order

**#5a and #5b are built; next: #6b → #5c → #6c → #6d (grilled + re-specced 2026-07-16, [ADR-0006](../adr/0006-device-keyed-push-evaluation.md)). Compact between each sub-issue. #7 and #8 can be done any time after #4.**

## Critical path

- [#3 Backend Internals](completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — ✅ merged
- [#4 HTTP API](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — ✅ merged
- [#10 Pre-5a hardening](completed/implement-spec-issue-10-hardening.md) ([GitHub](https://github.com/1mposer/time-it/issues/10)) — ✅ complete — typed `UpstreamError`, null-safe Meteosource adapter, DI factory router, `forecastStart` `Z` suffix, expanded test coverage (8 test files)
- [#5a Core iOS app](current/implement-spec-issue-5a-ios-core.md) — ✅ **built, live-verified, audited + merged to `main` (2026-07-12)** — read-only dashboard, GPS (silent Dubai fallback), client-authored seed Templates `POST`ed to the backend, per-activity `days[]` + 7-day detail. **No accounts** (Sign in with Apple cut, [ADR-0001](../adr/0001-no-accounts-guest-first.md)).
- [#5b Personalization layer](current/implement-spec-issue-5b-ios-personalization.md) — ✅ **built (2026-07-13, TDD)** — client-side **activity authoring** (add/edit/delete from Template or scratch, metric picker, threshold + optional-window editor incl. nocturnal wrap), `ActivityStore` local persistence, home location, client-side ADR-0005 validation mirror. Metric catalog behind the `MetricCatalogProviding` swap seam; **Pro/StoreKit deferred** (soft quantity cap, constant `ActivityStore.softCap`).
- Shared: [design-decisions-issue-5.md](current/design-decisions-issue-5.md) · [ios/guidelines/Guidelines.md](../../ios/guidelines/Guidelines.md)
- #6a Backend infrastructure — **CUT ([ADR-0001](../adr/0001-no-accounts-guest-first.md))**: accounts/auth removed; user prefs are client-side (#5b)
- [#6b Railway deployment](current/implement-spec-issue-6b-railway-deploy.md) — deploy the stateless engine (no DB), build-config iOS base URL
- [#5c Location onboarding](current/implement-spec-issue-5c-location-onboarding.md) — worldwide launch posture: **Dubai fallback deleted**, grayed empty state + "Enable location" / "Place your own location" (MapKit city search); soft prerequisite of #6c (registration needs a real location)
- [#6c Device registration + daily digest](current/implement-spec-issue-6c-registration-and-digest.md) — Postgres, snapshot upsert (`PUT /api/v1/devices/:deviceId`), `apns2` seam, per-device local-6am digest ([ADR-0006](../adr/0006-device-keyed-push-evaluation.md))
- [#6d Perfect-window detector](current/implement-spec-issue-6d-perfect-window-detector.md) — hourly, Perfect-only, once per (device, activity, bucket), buckets 0–1

## Parallel tracks (open now)

- [#7 Marine Data](current/implement-spec-issue-7-marine-data.md) ([GitHub](https://github.com/1mposer/time-it/issues/7)) — investigate Meteosource API tier before writing any code
- [#8 requireTrue threshold](current/implement-spec-issue-8-require-true-threshold.md) ([GitHub](https://github.com/1mposer/time-it/issues/8)) — small engine change, unblocks future stargazing features. **Scope grew (2026-07-15 review finding):** `validateRatingRequest` must also check a threshold's *shape* against its metric's *kind* — today a `type:"flag"` threshold on a numeric metric passes validation and then never fails an hour (silent false-Perfect); needs kind awareness in `metricCatalog.js` (the iOS mirror already rejects it)

## Notes

- Sub-issue specs live in the local spec files above — **the tree is the source of truth** (the #5 and #6 GitHub issues were removed).
- The old single-file #6 spec was superseded and deleted 2026-07-16 (git history keeps it); its decisions live in [ADR-0006](../adr/0006-device-keyed-push-evaluation.md) + the four spec files above.
- #6c requires an Apple Developer account ($99/year) + APNs `.p8` key — prerequisite before starting that sub-issue (see its header).
- When an issue is fully merged, move its spec to `docs/issues/completed/`.
