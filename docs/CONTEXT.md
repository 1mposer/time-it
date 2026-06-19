# time-it

> **Read the glossary below FIRST** — it defines the ubiquitous language used everywhere in this repo. Note: several terms (**Activity**, **Forecast**, **Index**, **Lite / Pro**, **Display metrics**) describe the *currently shipped code* and are **superseded by locked-but-unbuilt design**. ONLY AFTER you understand the terms, see [`STATUS.md`](STATUS.md) for the current project status and what is changing.

A backend engine that watches hourly weather forecasts and tells UAE outdoor hobbyists when conditions match their activity. Output is consumed by an iOS app that sends the user a push notification.

## Language

**Pursuit**:
The real-world outdoor thing a user does — Boat Fishing, Stargazing, Volleyball, Shore Fishing, and (future) Cycling, Hiking, Padel. A **Pursuit** ships as one or more **Activities** that the engine actually evaluates. The **Lite / Pro** tier split is the usual reason one Pursuit ships as multiple Activities.

**Activity**:
The code-level entity the decision engine evaluates — a specific configuration with an `id`, **Threshold** profile, and `displayMetrics` (currently `volleyball`, `boat-fishing-pro`, `boat-fishing-lite`, `shore-fishing`, `stargazing-lite`). One **Pursuit** may ship as multiple Activities under the **Lite / Pro** split; each Activity is independently rated and rendered as its own iOS dashboard card.

**Threshold**:
A min/max constraint on a single weather metric, optionally marked `required`. Failing a required threshold makes the hour **Bad**; failing only non-required thresholds makes it **Good** rather than **Perfect**.

**Threshold type — `flag`**:
A non-numeric **Threshold** for boolean fields. `{ type: "flag", forbidTrue: true }` fails the hour when the field is `true` (e.g. an active `dustAlert` or `seaWarning`). The inverse — `requireTrue`, passing only when the field is `true` — is planned for events the user wants to catch (meteor showers, solar eclipses); see Issue #8.

**Rating**:
The verdict on a single forecast hour against an **Activity**'s thresholds. One of **Perfect**, **Good**, or **Bad**.

**Perfect**:
All thresholds — required and non-required — pass.

**Good**:
All required thresholds pass; at least one non-required threshold fails.

**Bad**:
At least one required threshold fails.

**Window**:
The longest contiguous block of forecast hours sharing the same qualifying **Rating** (Perfect, falling back to Good). The decision engine returns at most one **Window** per evaluation — the best one found.
_Avoid_: run

**Session**:
The user's actual outdoor activity time (e.g., Abdulla's 3-hour Sunday cycling block). A **Session** is shorter than or equal to a **Window** — the **Window** says when conditions are right; the **Session** is when the user actually goes out.

**User preferences**:
A user's chosen **Activity** plus their **Threshold** overrides. In code: `userPrefs`.

**Forecast**:
24 hourly entries starting at "now", fetched from the weather provider via an **Adapter** and normalized to a unified schema.

**Forecast start**:
The ISO 8601 UTC timestamp of the first hourly entry in the **Forecast**, with an explicit `Z` suffix (e.g. `"2026-05-19T15:00:00Z"`). Stored on the parse result as `forecastStart` and propagated to the API response. The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode it without custom formatting. The iOS app combines it with each hourly entry's **Index** to render clock times. *(Under the locked design the app renders using the response's `timezone` field — the **forecast location's** IANA zone — not the device timezone, so hour labels and day boundaries match the server's calendar bucketing; see [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).)*

**Index**:
The 0–23 position of a forecast entry within the 24-hour **Forecast** array. Monotonic and timezone-agnostic — `index: 5` always means "the 6th hour after **Forecast start**", regardless of clock time. Used by the decision engine as the canonical position primitive (`startIndex`, `endIndex`, `duration`) and surfaced on every hourly object in the API response as `index`. Introduced in [Issue #1](issues/completed/implement-spec-issue-1.md) to replace **Clock hour** in the engine output after midnight-crossover bugs.

**Clock hour**:
The 0–23 UTC clock hour a forecast entry represents (e.g. `hour: 15` for 15:00 UTC), stored on every hourly object as `hour`. Wraps at midnight, so a chronological scan over clock hours is non-monotonic — unsafe for ordering, duration math, or **Window** detection. Use **Index** for those; reserve `hour` for clients that combine it with **Forecast start** and a known timezone to render local clock times for the user.
_Avoid_: using `hour` as a position primitive in engine or backend logic — that is the bug pattern [Issue #1](issues/completed/implement-spec-issue-1.md) fixed.

**Adapter**:
A provider-specific module that extracts the unified hourly fields from a raw API response. Currently only Meteosource.

**Principle — provider-specifics stop at the adapter boundary.** Everything a provider does differently — field names, units, null handling, date format, *and how many hourly entries it serves* — is reconciled in its **Adapter** (with the `parse.js` normalisation step) so the decision engine only ever sees the unified, agnostic schema. A direct corollary: **no provider's forecast horizon is baked into the contract.** The horizon is whatever clean hourly data the provider returns, consumed up to a 7-day (168-hour) **ceiling** — fewer is valid, the last day may be partial, and the engine is count-agnostic. The system **never fabricates or interpolates** hours to hit a target count; doing so would resurrect the false-**Perfect** hazard the absent-data guard (`checkThreshold` null-fails) exists to prevent. *(This horizon model is locked-but-unbuilt — current code still fixes the **Forecast** at 24 entries; see [`STATUS.md`](STATUS.md), [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md).)*

**Principle — locale/time normalises at its own boundary, the same way.** Timezone is the second instance of the adapter pattern. The forecast **location's** IANA zone (supplied by the provider, e.g. `Asia/Dubai` — not a hardcoded offset) is normalised once, and a **time-boundary module** tags each hour with a local-calendar-day key so the decision engine groups results **by day** without ever reasoning about timezones, offsets, or DST. The engine stays agnostic to locale exactly as it is to providers. Day buckets are the **forecast location's** calendar days, not the device's — a client-side location-shift guardrail keeps the user's active location aligned with where they are. *(Locked-but-unbuilt; see [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).)*

**Lite / Pro**:
Tier variants of a **Pursuit**, each shipped as its own **Activity**, keyed to data availability. **Lite** Activities use fields available on Meteosource's free tier (temperature, wind, cloud cover, humidity, UV); **Pro** Activities use fields requiring premium or specialised data (Douglas scale, swell height — see Issue #7; atmospheric transparency, moon phase — deferred). Not every Pursuit has both tiers: currently only Boat Fishing ships as both `boat-fishing-lite` and `boat-fishing-pro`. Stargazing Pro is deferred until an astronomy data source is integrated.

**Display metrics**:
The ordered list of metric key names an **Activity** declares as relevant to its **Rating**. Stored on the activity definition as `displayMetrics`. The backend decides which metrics matter per activity; the iOS app renders them generically without hardcoding per-activity logic. Example: `["temp", "windSpeed", "humidity", "uV"]` for Volleyball.

**Darkness (Bortle scale)**:
A sky-quality measurement on the standard Bortle scale (1–9). **1 = darkest, most pristine sky (best for stargazing); 9 = heavily light-polluted urban sky (worst)**. A threshold of `max: 4` means the sky must be rural-class or darker to pass. Currently hardcoded to `0` in `parse.js` (no premium data source); marked `required: false` so it downgrades to **Good** rather than **Bad** until real data is integrated. Also omitted from `displayMetrics` so the iOS Stargazing card does not surface the misleading hardcoded value.
_Avoid_: treating higher Bortle numbers as better — that is the inverted convention used in the old code and is incorrect.

**Douglas scale**:
A 0–9 international scale describing sea state by significant wave height. **0 = calm (glassy)**, 3 = slight (0.5–1.25 m), 5 = rough (2.5–4 m), 9 = phenomenal (over 14 m). Used as a numeric **Threshold** by fishing **Activities** — `boatFishingPro` requires `max: 3`. Currently hardcoded to `0` in `parse.js`; real values will be wired in [Issue #7](issues/current/implement-spec-issue-7-marine-data.md). Also omitted from `displayMetrics` until real data flows.

**Sea warning**:
A boolean flag indicating an active maritime-authority alert (e.g. gale warning, small-craft advisory). Used as a `flag` **Threshold** with `forbidTrue: true` — when `true`, fishing **Activities** rate the hour as **Bad**. Currently hardcoded to `false` in `parse.js`; a UAE maritime authority API source has not yet been identified.

## Relationships

- A **Pursuit** ships as one or more **Activities**; each Activity has its own **Threshold** profile and `displayMetrics`.
- A **User** picks an **Activity** and supplies **User preferences** (threshold overrides).
- The decision engine evaluates each hour of the **Forecast** against the user's **Thresholds**, producing a **Rating** per hour, then finds the longest **Window**.
- A **Session** fits inside a **Window** — the engine produces the **Window**; the user (or iOS app) chooses where to place the **Session**.

## Example dialogue

> **Dev:** "The engine returned a 6-hour **Window** of Perfect cycling weather. Does Abdulla cycle for all 6 hours?"
> **Domain expert:** "No — Abdulla's **Session** is 3 hours on Sunday. The **Window** tells him *when he could* go out. He picks where his **Session** fits inside it."
> **Dev:** "What if no hour clears the required **Thresholds**?"
> **Domain expert:** "Then there's no **Window** for this **Forecast**. The iOS app shows 'no window in the next 24 hours' and sends no notification."

## Tests

For the full test inventory (unit tests for the adapter, parser, fetch, getWeather, decision engine, and HTTP route), see [`CLAUDE.md`](../CLAUDE.md#tests). `tests/decision/decision_engine.test.js` remains the canonical reference for the core **Window** evaluation logic — midnight crossover, single-hour window, no qualifying hours, Perfect preferred over Good, last-element runs, the null-value-fails-threshold guard, and the strict-`>` tie-break.
