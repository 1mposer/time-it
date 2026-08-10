# time-it

> **Read the glossary below FIRST** — it defines the ubiquitous language used everywhere in this repo. The Phase-2 contract flip is now built: **Activity** (caller-supplied), **Lite / Pro** (metric-access + quantity, client-enforced), and **Display metrics** (user-chosen) describe the *shipped* code. ONLY AFTER you understand the terms, see [`STATUS.md`](STATUS.md) for the current project status and what remains.

A backend engine that watches hourly weather forecasts and tells outdoor hobbyists when conditions match their activity — a **worldwide** product, UAE-first in marketing only. Output is consumed by an iOS app; server-side push is designed in [ADR-0006](adr/0006-device-keyed-push-evaluation.md): the **Digest** backend (Issue #6c — registration, Postgres, APNs seam, digest job) and the **Perfect-window alert** backend (Issue #6d — hourly detector, bucket-date dedup) are both built, merged (2026-08-01), and deployed live (2026-08-03); the iOS opt-in client is still to come.

## Language

**Pursuit**:
The real-world outdoor thing a user does — Cycling, Running, Stargazing, Fishing (shipped today as the **Fishing Lite** Template), and whatever else a user authors from scratch. A **Pursuit** ships as one or more **Activities** that the engine actually evaluates. The **Lite / Pro** tier split is the usual reason one Pursuit ships as multiple Activities (e.g. a future **Fishing Pro** alongside Fishing Lite).

**Activity**:
The entity the decision engine evaluates — a configuration with a client-authored `id`, **Threshold** profile, `displayMetrics`, and an optional time-of-day **Window**. Activities are **caller-supplied**: the client authors them and sends them in the `POST /api/v1/rating` body; the engine holds **no** activity list and is activity-agnostic ([ADR-0002](adr/0002-activity-agnostic-engine.md), [ADR-0005](adr/0005-custom-activity-request-schema.md)). One **Pursuit** may be authored as multiple Activities; each is independently rated and rendered as its own iOS dashboard card. (Curated seed Activities now live client-side as Templates, not in the backend.)

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
The longest contiguous block of forecast hours sharing the same qualifying **Rating** (Perfect, falling back to Good). The decision engine returns at most one **Window** per bucket (one `days[]` entry per bucket; see [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)). For a **diurnal** activity a bucket is one **forecast-location local calendar day**; for a **nocturnal** activity (one whose time-of-day window wraps midnight) a bucket is a **night** (the **night-stitch**). So `days.length` is **per-activity** — never assume it is equal across activities.
_Avoid_: calling a **Window** a *run* — "run" is a loose synonym for the contiguous block of qualifying hours (it survives only in code comments); use **Window** consistently in domain language.

**Time-of-day window**:
An optional per-**Activity** `{ startHour, endHour }` (integers `0..23`, **forecast-location local** hours, half-open `[startHour, endHour)`) sent in the request that restricts evaluation to those hours each day. Absent = whole day; `startHour < endHour` = same-day; `startHour > endHour` = **midnight-wrap (nocturnal)**, the only nocturnal signal, which licenses the night-stitch; `startHour === endHour` is rejected. The client sends raw local hours and does **zero** timezone math — the time-boundary module tags each hour's `localHour` and the engine compares integers. See [ADR-0005](adr/0005-custom-activity-request-schema.md). *(Locked UX direction, 2026-07-20: the post-#6 range-first wizard — Figma "Main - Time it" — makes the range **mandatory in the authoring UI**; the wire keeps `window` optional exactly as above, so this is a UI rule, not a contract change. Ranges are **whole-hour** — `localHour` is an integer, so minute-granular windows would be an engine + wire change. Until that wave lands, the built editor's window stays optional.)*

**Night-stitch**:
The one controlled cross-midnight exception to per-calendar-day bucketing ([ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) amendment). A wrapped time-of-day window makes an Activity nocturnal; the engine then buckets by **night** — `night N = [day N startHour, day N+1 endHour)`, pairing an evening with the next morning. The bucket's `dayIndex` is the **evening's** calendar day (`0` = tonight); the early-morning tail belongs to that evening, not a separate next-day window; the pre-horizon orphan morning (day-0 hours whose evening precedes the forecast) is dropped. Opt-in and bounded (exactly one midnight crossing), so it cannot resurrect unbounded cross-day fusion.

**Metric catalog**:
The server-side source of truth (`src/weather/metricCatalog.js`) for which weather metrics carry **live** data versus a **coming-soon** placeholder. Request validation hard-rejects (`400`) any **Threshold** or **Display metric** on a non-live or unknown metric — a threshold on placeholder data would pass trivially (a silent false **Perfect**). See [ADR-0005](adr/0005-custom-activity-request-schema.md).

**Session**:
The user's actual outdoor activity time (e.g., Abdulla's 3-hour Sunday cycling block). A **Session** is shorter than or equal to a **Window** — the **Window** says when conditions are right; the **Session** is when the user actually goes out.

**User preferences**:
The user's authored **Activity** list, home location, and settings — **client-side only** (`ActivityStore`/`PreferencesStore` in UserDefaults, Issue #5b; no server-side preferences API, [ADR-0001](adr/0001-no-accounts-guest-first.md)). The **Device snapshot** is a push-only server copy of some of this state, not a preferences store.

**Active location**:
The location the app currently rates against, resolved client-side in fixed order: home (picked city) → live GPS fix → last resolved location (persisted from the most recent successful rating) → **none**, which renders the grayed empty state with the two onboarding CTAs ("Enable location" / "Place your own location"). The silent Dubai fallback was **deleted by Issue #5c** — the app never fabricates a location.
_Avoid_: letting any fallback location reach push registration — a **Device snapshot** requires a real home or GPS location ([ADR-0006](adr/0006-device-keyed-push-evaluation.md)).

**Device**:
The anonymous push identity: a client-minted install UUID in the Keychain plus the current APNs token ([ADR-0001](adr/0001-no-accounts-guest-first.md)). Identifies an *install*, never a human — there are no accounts.

**Device snapshot**:
The device-keyed server-side copy of `{ APNs token, home lat/lon, authored Activities }` a **Device** uploads via full-snapshot upsert (`PUT /api/v1/devices/:deviceId`) when notifications are enabled. Client-authoritative, last-write-wins; re-upserted on any change; deleted on opt-out. Exists **only** for the push path — the `/rating` path stays stateless. See [ADR-0006](adr/0006-device-keyed-push-evaluation.md).

**Digest**:
The daily push summary, sent at the **Device's local 6am**: today's/tonight's **Window** per Activity, plus week-ahead **Perfect** highlights (buckets 2 through the end of each Activity's horizon — `days.length` is per-Activity, never a fixed 7). At most one per Device per day; not sent when nothing qualifies. Issue #6c.

**Perfect-window alert**:
The event push produced by the hourly *detector* job (Issue #6d): fires on the **first Perfect Window per (Device, Activity, bucket)** within buckets 0–1 (~48h). Perfect-only — a good→perfect upgrade alerts inherently as the bucket's first Perfect; Good windows surface in the **Digest** instead. Deduplicated by bucket date, never by index (indices re-base every fetch).
_Avoid_: the old grill name *Window Watch* — use **Perfect-window alert**.

**Forecast**:
A 7-day rolling window of hourly entries starting at "now", fetched from the weather provider via an **Adapter** and normalized to a unified schema. The count is **provider-determined, up to a 168-hour (7×24) ceiling** (Meteosource `flexi` returns ~161–168) — fewer is valid, the last day may be partial, and the system never fabricates hours to hit a target. Consumers must read the actual length, never assume a fixed count. See [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md).

**Forecast start**:
The ISO 8601 UTC timestamp of the first hourly entry in the **Forecast**, with an explicit `Z` suffix (e.g. `"2026-05-19T15:00:00Z"`). Stored on the parse result as `forecastStart` and propagated to the API response. The `Z` suffix is required so Swift's default `ISO8601DateFormatter` can decode it without custom formatting. The response also carries a top-level **`timezone`** — the **forecast location's** IANA zone (e.g. `Asia/Dubai`) — and the iOS app renders clock times and day boundaries in **that** zone (combining `forecastStart` + `timezone` + each entry's **Index**), not the device timezone, so hour labels and day boundaries match the server's calendar bucketing. See [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).

**Index**:
The `0..N-1` position of a forecast entry within the **Forecast** array (`N` ≤ 168). Monotonic and timezone-agnostic — `index: 5` always means "the 6th hour after **Forecast start**", regardless of clock time. Used by the decision engine as the canonical position primitive (`startIndex`, `endIndex`, `duration` are **global** indices into the array) and surfaced on every hourly object in the API response as `index`. Introduced in [Issue #1](issues/completed/implement-spec-issue-1.md) to replace **Clock hour** in the engine output after midnight-crossover bugs.

**Clock hour**:
The 0–23 UTC clock hour a forecast entry represents (e.g. 15:00 UTC). No longer a wire field — the `hour` field was **dropped** from the hourly object ([ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md)); the client derives clock times from **Forecast start** + the response **`timezone`** + **Index**. Clock hour wraps at midnight, so a chronological scan over it is non-monotonic — unsafe for ordering, duration math, or **Window** detection.
_Avoid_: using a derived clock hour as a position primitive in engine or backend logic — that is the bug pattern [Issue #1](issues/completed/implement-spec-issue-1.md) fixed; use **Index**.

**Adapter**:
A provider-specific module that extracts the unified hourly fields from a raw API response. Currently only Meteosource.

**Principle — provider-specifics stop at the adapter boundary.** Everything a provider does differently — field names, units, null handling, date format, *and how many hourly entries it serves* — is reconciled in its **Adapter** (with the `parse.js` normalisation step) so the decision engine only ever sees the unified, agnostic schema. A direct corollary: **no provider's forecast horizon is baked into the contract.** The horizon is whatever clean hourly data the provider returns, consumed up to a 7-day (168-hour) **ceiling** — fewer is valid, the last day may be partial, and the engine is count-agnostic. The system **never fabricates or interpolates** hours to hit a target count; doing so would resurrect the false-**Perfect** hazard the absent-data guard (`checkThreshold` null-fails) exists to prevent. *(Built in Phase 1; see [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md).)*

**Principle — locale/time normalises at its own boundary, the same way.** Timezone is the second instance of the adapter pattern. The forecast **location's** IANA zone (supplied by the provider, e.g. `Asia/Dubai` — not a hardcoded offset) is normalised once, and a **time-boundary module** tags each hour with a local-calendar-day key so the decision engine groups results **by day** without ever reasoning about timezones, offsets, or DST. The engine stays agnostic to locale exactly as it is to providers. Day buckets are the **forecast location's** calendar days, not the device's — a client-side location-shift guardrail keeps the user's active location aligned with where they are. *(Built in Phase 1: the time-boundary module is `src/weather/timeBoundary.js`; see [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md), [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md).)*

**Lite / Pro**:
The user's subscription tier, enforced as **metric-access + quantity gating** (grill Q3) — **not** as separate `-lite`/`-pro` Activity variants. A tier gates which *metrics* the user may choose and how many *Activities* they may author. This gating is **client-enforced**: the backend stays activity-agnostic and does not check tier. (The `~50`-activity request ceiling in [ADR-0005](adr/0005-custom-activity-request-schema.md) is a DoS guard, **not** a tier/quantity gate.) Premium metrics requiring specialised data (Douglas scale, swell height — see Issue #7) are **coming-soon** in the metric catalog until their adapters land. (**Moon phase** already has a live adapter — `metricCatalog.js` LIVE_METRICS — and ships today as a display-only metric on the Stargazing Template; it is not coming-soon.)

**Display metrics**:
The ordered list of metric key names an **Activity** declares as relevant to its **Rating**, carried as `displayMetrics` in the request. **User-chosen** (not backend-decided): the client picks which metrics appear on each card, and the backend echoes the list through. It is the render **superset** — `thresholds.keys ⊆ displayMetrics` — so a metric can be shown without being judged ("show-but-don't-judge"). The iOS app renders them generically without hardcoding per-activity logic. Example: `["temp", "windSpeed", "humidity", "uV"]` for Volleyball.

**Darkness (Bortle scale)**:
A sky-quality measurement on the standard Bortle scale (1–9). **1 = darkest, most pristine sky (best for stargazing); 9 = heavily light-polluted urban sky (worst)**. A threshold of `max: 4` means the sky must be rural-class or darker to pass. Currently hardcoded to `0` in `parse.js` (no astronomy data source), so it is a **coming-soon** metric: a request that thresholds *or* displays `darkness` is hard-rejected (`400`) until real data is integrated (the false-Perfect guard — see **Metric catalog**). It still appears as a `0` placeholder in the `hours[]` timeline shape.
_Avoid_: treating higher Bortle numbers as better — that is the inverted convention used in the old code and is incorrect.

**Douglas scale**:
A 0–9 international scale describing sea state by significant wave height. **0 = calm (glassy)**, 3 = slight (0.5–1.25 m), 5 = rough (2.5–4 m), 9 = phenomenal (over 14 m). Would be used as a numeric **Threshold** by a boat-fishing Activity — e.g. `max: 3` — once real data lands; no such Activity id exists in the codebase today (Douglas scale is hard-rejected as coming-soon). Currently hardcoded to `0` in `parse.js`; real values arrive with the deferred marine-data work ([GitHub #7](https://github.com/1mposer/time-it/issues/7) — see [ROADMAP §Deferred](issues/ROADMAP.md)). Also omitted from `displayMetrics` until real data flows.

**Sea warning**:
A boolean flag indicating an active maritime-authority alert (e.g. gale warning, small-craft advisory). Used as a `flag` **Threshold** with `forbidTrue: true` — when `true`, fishing **Activities** rate the hour as **Bad**. Currently hardcoded to `false` in `parse.js`; a UAE maritime authority API source has not yet been identified.

## Relationships

- A **Pursuit** is authored as one or more **Activities**; each Activity has its own **Threshold** profile, `displayMetrics`, and optional time-of-day **Window**.
- A **User** authors **Activities** client-side (from Templates or scratch) and the iOS app sends them in the `POST /api/v1/rating` body; the backend holds no activity list.
- The decision engine evaluates each hour of the **Forecast** against each Activity's **Thresholds**, producing a **Rating** per hour, then finds the longest **Window** per bucket (calendar day, or **night** for a nocturnal Activity).
- A **Session** fits inside a **Window** — the engine produces the **Window**; the user (or iOS app) chooses where to place the **Session**.
- A **Device** (opt-in) registers a **Device snapshot**; the server's **Digest** and **Perfect-window alert** jobs evaluate the snapshot's Activities with the same engine the `/rating` route uses ([ADR-0006](adr/0006-device-keyed-push-evaluation.md)).

## Example dialogue

> **Dev:** "The engine returned a 6-hour **Window** of Perfect cycling weather. Does Abdulla cycle for all 6 hours?"
> **Domain expert:** "No — Abdulla's **Session** is 3 hours on Sunday. The **Window** tells him *when he could* go out. He picks where his **Session** fits inside it."
> **Dev:** "What if no hour clears the required **Thresholds**?"
> **Domain expert:** "Then there's no **Window** for that day. The card reads 'No window today' (a nocturnal Activity: 'No window tonight') — it never rolls forward to a later day; the detail timeline still shows the rest of the week — and no notification is sent."

## Tests

For the full test inventory (unit tests for the adapter, parser, fetch, getWeather, decision engine, and HTTP route), see [`CLAUDE.md`](../CLAUDE.md#tests). `tests/decision/decision_engine.test.js` remains the canonical reference for the core **Window** evaluation logic — midnight crossover, single-hour window, no qualifying hours, Perfect preferred over Good, last-element runs, the null-value-fails-threshold guard, and the strict-`>` tie-break.
