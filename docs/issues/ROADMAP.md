# Roadmap

## Build order

**#3 must be done first. #4 → #5 → #6 must be done in that order. #7 and #8 can be done any time after #3.**

## Critical path

- [#3 Backend Internals](current/implement-spec-issue-3-backend-internals.md) — start here, everything depends on it
- [#4 HTTP API](current/implement-spec-issue-4-http-api.md) — requires #3
- [#5 iOS App](current/implement-spec-issue-5-ios-swiftui.md) — requires #4 running locally
- [#6 Deploy + Notifications](current/implement-spec-issue-6-deploy-and-notifications.md) — requires #4 and #5

## Parallel tracks (open after #3)

- [#7 Marine Data](current/implement-spec-issue-7-marine-data.md) — investigate Meteosource API tier before writing any code
- [#8 requireTrue threshold](current/implement-spec-issue-8-require-true-threshold.md) — small engine change, unblocks future stargazing features

## Notes

- #6 Part B (push notifications) needs an Apple Developer account — scaffold is written, implementation is deferred.
- When an issue is merged, move its spec to `docs/issues/completed/`.
