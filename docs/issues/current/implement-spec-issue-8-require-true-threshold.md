# Implementation spec — Issue #8: Add `requireTrue` threshold type to decision engine

> ⚠️ **STALE — predates the Phase 1/2 rebuild.** Any language below about "activity definitions", `starGazingLite`, or editing activity files is obsolete: the curated `src/activities/*` list was **deleted** — activities are **caller-supplied** in the request body ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)/[ADR-0005](../../adr/0005-custom-activity-request-schema.md)); `requireTrue` acceptance now means `validateRatingRequest` + `checkThreshold` + tests, not activity files. **Scope grew 2026-07-15** (fresh-session #5b review; see [STATUS.md](../../STATUS.md) §5(g) + ROADMAP): `validateRatingRequest` never checks that a threshold's *shape* matches its metric's *kind* — a `type:"flag"` threshold on a numeric metric passes validation, then never fails an hour in `checkThreshold` (silent false-Perfect). The server metric catalog needs kind awareness; the iOS client mirror already rejects this. Reconcile against ADR-0005 §6 + STATUS.md before implementing.

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #3 (Backend Internals)](../completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — `forbidTrue` flag type must be in place first

---

## 1. Context

The decision engine's `checkThreshold` supports numeric bounds (`min`/`max`) and `forbidTrue`
(penalise a boolean alert being present). There is no inverse: a condition that must be
**present** to pass. This blocks activity definitions where a rare event is desirable:

- `totalSolarEclipse: true` — removed from `starGazingLite` in Issue #3 for this reason
- Meteor shower peaks, planet oppositions — calendar-driven events the user wants to catch

---

## 2. Proposed change

Add a `requireTrue` branch to `checkThreshold` in `src/decision/decision_engine.js`:

```js
if (config.type === "flag" && config.requireTrue && value !== true) return false;
```

Activity definitions would use:

```js
totalSolarEclipse: { requireTrue: true, type: "flag", required: false },
```

`required: false` downgrades to **Good** rather than **Bad** — appropriate for optional events.

---

## 3. Out of scope

- Astronomy data source — `totalSolarEclipse` is not in Meteosource. This issue adds the
  engine capability only; wiring real calendar data is a separate concern.
- Changes to activity files — updated once the data source is confirmed.

---

## 4. Related artifacts

- [Issue #3 (Backend Internals)](../completed/implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — introduced `forbidTrue`; `requireTrue` is its counterpart.
- [Issue #7 (Marine Data)](implement-spec-issue-7-marine-data.md) ([GitHub](https://github.com/1mposer/time-it/issues/7)) — same pattern: engine capability before data source.
