# Issue #8 — `requireTrue` threshold type + threshold-kind validation (stub)

> **Stub (2026-08-10):** the original spec predated the Phase 1/2 rebuild and prescribed edits to the deleted `src/activities/*` files; it was replaced by this stub so nothing stale can be executed (git history keeps the original). Expand into a full spec only when promoted. [GitHub #8](https://github.com/1mposer/time-it/issues/8) · glossary: [`CONTEXT.md`](../../CONTEXT.md).

Two work items, one issue:

1. **`requireTrue` flag threshold** — the inverse of `forbidTrue`: `{ type: "flag", requireTrue: true, required: false }` fails the hour when the field is not `true` (meteor showers, eclipses — rare events the user wants to *catch*; `required: false` downgrades to Good rather than Bad). Engine: one branch in `checkThreshold` (`src/decision/decision_engine.js`). Wire: [ADR-0005](../../adr/0005-custom-activity-request-schema.md) currently hard-rejects `requireTrue` ("no wire surface for unbuilt behaviour") — lifting that rejection is part of this issue. Blocked on an astronomy/calendar data source (not Meteosource).

2. **Threshold-shape vs metric-kind validation** (2026-07-15 review finding) — `validateRatingRequest` accepts a `type:"flag"` threshold on a *numeric* metric; it then never fails an hour in `checkThreshold` (a silent false-Perfect). Fix: `src/weather/metricCatalog.js` gains a per-metric kind (`numeric` | `flag`); validation rejects mismatches. The iOS client mirror already rejects this, so the server change is parity/defence-in-depth — unreachable from the shipped client.

**Mirror tax note:** once spec 14's `HourQuality` client evaluator exists, any new threshold semantics (including `requireTrue`) must land in **both** engines — see [ADR-0007](../../adr/0007-client-side-mirrors.md).

**Promote when:** an astronomy source is identified, or a non-mirrored client can author activities. Until then: DEFER ([ROADMAP](../ROADMAP.md)).
