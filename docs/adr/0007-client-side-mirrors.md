# Client-side mirrors are the accepted price of the frozen wire

Status: Accepted (2026-08-10).

The `/rating` wire contract ([ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md)/[0004](0004-day-bucketed-rating-wire-shape.md)/[0005](0005-custom-activity-request-schema.md)) is deliberately frozen: the server returns day-bucketed verdicts plus raw hours, and evolving it is a versioned event, not a routine change. Several client features need server-owned logic at finer grain than the wire carries, and the recurring resolution has been to **mirror a slice of that logic client-side**. This decision had been made implicitly three times; this ADR makes it explicit, once.

**Decision.** A client-side mirror of a bounded slice of server logic is acceptable when (a) the wire alternative would be a contract change, (b) the slice is small and pure, and (c) a pinning test binds the mirror to server behavior (a committed real-response fixture, or a table pinned in both suites).

**The mirrors (as of 2026-08-10):**

1. `StaticMetricCatalog` (iOS) ↔ `src/weather/metricCatalog.js` — the LIVE metric set. Pinned by tests on both sides; the `MetricCatalogProviding` seam swaps in a `RemoteMetricCatalog` when the metrics route ships.
2. `TimeDeriver` (iOS) ↔ `src/jobs/labels.js` — clock/day-label derivation (CLAUDE.md calls them twins). Shared known limitation: half-hour zones render `ha`-style labels :30 off.
3. `HourQuality` (iOS, spec 14 §3) ↔ `evaluateHour` (`src/decision/decision_engine.js`) — per-hour tier evaluation for the gradient card. Pinned by the spec 14 §3 invariant test against `RealBackendResponseFixture` (greenest run must coincide with the server's returned window — `HourQualityInvariantTests`).

**The rule.** Any change to threshold semantics (e.g. #8's `requireTrue` or kind-validation) or label derivation lands in **both** engines in the same wave, with the pinning test updated. Drift between a mirror and the server is a release-blocking bug.

**Rejected alternative (recorded, revisitable): additive per-hour tiers on the wire.** The server could return each activity's per-hour tier as an additive field — the tolerant iOS decoder would not break. Rejected *for now* because it puts server work on the ship-critical path (spec 14 hard-fences "zero server diffs") and grows the payload. **Revisit trigger:** the next new mirror, or the first mirror-drift bug — at that point per-hour tiers on the wire likely become the cheaper side of the trade.

**Standing context.** [ADR-0002](0002-activity-agnostic-engine.md) rejected a *full* client-side engine ("duplicates the crown-jewel Window logic, two engines drift") — that rejection stands: the Window search, night-stitch, and bucketing remain server-only. Mirrors are bounded slices, never the search.
