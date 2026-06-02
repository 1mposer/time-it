# Roadmap

## Build order

**#4 is the current focus. #4 → #5 → #6 must be done in that order. #7 and #8 can be done any time after #3 (already done).**

## Critical path

- [#3 Backend Internals](completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — ✅ merged
- [#4 HTTP API](current/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — **start here**
- [#5 iOS App](current/implement-spec-issue-5-ios-swiftui.md) ([GitHub](https://github.com/1mposer/time-it/issues/5)) — requires #4 running locally
- [#6 Deploy + Notifications](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6)) — requires #4 and #5

## Parallel tracks (open now)

- [#7 Marine Data](current/implement-spec-issue-7-marine-data.md) ([GitHub](https://github.com/1mposer/time-it/issues/7)) — investigate Meteosource API tier before writing any code
- [#8 requireTrue threshold](current/implement-spec-issue-8-require-true-threshold.md) ([GitHub](https://github.com/1mposer/time-it/issues/8)) — small engine change, unblocks future stargazing features

## Notes

- #6 Part B (push notifications) needs an Apple Developer account — scaffold is written, implementation is deferred.
- When an issue is merged, move its spec to `docs/issues/completed/`.
