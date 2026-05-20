# time-it

A backend engine that watches hourly weather forecasts and tells UAE outdoor hobbyists when conditions match their activity. Output is consumed by an iOS app that sends the user a push notification.

## Language

**Activity**:
A specific outdoor pursuit (Cycling, Hiking, Padel, Volleyball, Shore Fishing, Boat Fishing, Stargazing). Each ships with a default **Threshold** profile.

**Threshold**:
A min/max constraint on a single weather metric, optionally marked `required`. Failing a required threshold makes the hour **Bad**; failing only non-required thresholds makes it **Good** rather than **Perfect**.

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

**Adapter**:
A provider-specific module that extracts the unified hourly fields from a raw API response. Currently only Meteosource.

**Lite / Pro**:
The two preset **Threshold** profiles per **Activity**. **Lite** uses free-tier metrics; **Pro** uses premium metrics (atmospheric transparency, swell height, Douglas scale, moon phase) and corresponds to a paid subscription tier.

**Display metrics**:
The ordered list of metric key names an **Activity** declares as relevant to its **Rating**. Stored on the activity definition as `displayMetrics`. The backend decides which metrics matter per activity; the iOS app renders them generically without hardcoding per-activity logic. Example: `["temp", "windSpeed", "humidity", "uV"]` for Volleyball.

**Darkness (Bortle scale)**:
A sky-quality measurement on the standard Bortle scale (1–9). **1 = darkest, most pristine sky (best for stargazing); 9 = heavily light-polluted urban sky (worst)**. A threshold of `max: 4` means the sky must be rural-class or darker to pass. Currently hardcoded to `0` in `parse.js` (no premium data source); marked `required: false` so it downgrades to **Good** rather than **Bad** until real data is integrated.
_Avoid_: treating higher Bortle numbers as better — that is the inverted convention used in the old code and is incorrect.

## Relationships

- A **User** picks one **Activity** and supplies **User preferences** (threshold overrides).
- An **Activity** has many **Thresholds** and ships in **Lite** and **Pro** profiles.
- The decision engine evaluates each hour of the **Forecast** against the user's **Thresholds**, producing a **Rating** per hour, then finds the longest **Window**.
- A **Session** fits inside a **Window** — the engine produces the **Window**; the user (or iOS app) chooses where to place the **Session**.

## Example dialogue

> **Dev:** "The engine returned a 6-hour **Window** of Perfect cycling weather. Does Abdulla cycle for all 6 hours?"
> **Domain expert:** "No — Abdulla's **Session** is 3 hours on Sunday. The **Window** tells him *when he could* go out. He picks where his **Session** fits inside it."
> **Dev:** "What if no hour clears the required **Thresholds**?"
> **Domain expert:** "Then there's no **Window** for this **Forecast**. The iOS app shows 'no window in the next 24 hours' and sends no notification."

## Tests

- `tests/decision/decision_engine.test.js` — five unit tests covering the core **Window** evaluation logic (midnight crossover, single-hour window, no qualifying hours, Perfect preferred over Good, Good fallback).
- `tests/decision/evaluateAll.test.js` — smoke test verifying `evaluateAll(hours)` returns an array where every element contains `activityId`, `label`, `rating`, and `displayMetrics`.
