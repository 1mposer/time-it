# Roadmap

## Build order

**#5a is the current focus. Compact between each sub-issue. #7 and #8 can be done any time after #4.**

## Critical path

- [#3 Backend Internals](completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — ✅ merged
- [#4 HTTP API](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — ✅ merged
- [#10 Pre-5a hardening](completed/implement-spec-issue-10-hardening.md) ([GitHub](https://github.com/1mposer/time-it/issues/10)) — ✅ complete — typed `UpstreamError`, null-safe Meteosource adapter, DI factory router, `forecastStart` `Z` suffix, expanded test coverage (8 test files)
- [#5a Core iOS app](current/implement-spec-issue-5a-ios-core.md) ([GitHub](https://github.com/1mposer/time-it/issues/5)) — **current focus** — dashboard, GPS, Sign in with Apple (client-only), client-authored activity cards (seed Templates `POST`ed to the backend)
- [#5b Personalization layer](current/implement-spec-issue-5b-ios-personalization.md) ([GitHub](https://github.com/1mposer/time-it/issues/5)) — onboarding, activity filtering, home location, StoreKit Pro gating
- Shared: [design-decisions-issue-5.md](current/design-decisions-issue-5.md) · [ios/guidelines/Guidelines.md](../../ios/guidelines/Guidelines.md)
- [#6a Backend infrastructure](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6)) — PostgreSQL, Sign in with Apple verification, JWT auth, user preferences API
- [#6b Railway deployment](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6)) — deploy to Railway, update iOS app to live URL
- [#6c Push notifications](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6)) — APNs, daily digest cron, Perfect window detector cron

## Parallel tracks (open now)

- [#7 Marine Data](current/implement-spec-issue-7-marine-data.md) ([GitHub](https://github.com/1mposer/time-it/issues/7)) — investigate Meteosource API tier before writing any code
- [#8 requireTrue threshold](current/implement-spec-issue-8-require-true-threshold.md) ([GitHub](https://github.com/1mposer/time-it/issues/8)) — small engine change, unblocks future stargazing features

## Notes

- Sub-issue specs (#5a, #5b, #6a, #6b, #6c) live in the GitHub issue bodies for #5 and #6, and are mirrored in the local spec files above.
- #6c requires an Apple Developer account ($99/year) — prerequisite before starting that sub-issue.
- When an issue is fully merged, move its spec to `docs/issues/completed/`.
