# The `POST /api/v1/rating` request body is a flat `{ lat, lon, activities[] }`; activities carry client-authored id, display-superset, threshold-subset, and a half-open local-hour window

The activity-agnostic engine ([ADR-0002](0002-activity-agnostic-engine.md)) requires the caller to *send* the activity profiles it evaluates, which flips `GET /api/v1/rating?lat=&lon=` to a **`POST`** carrying a JSON body. This ADR pins that body — the **input-side twin of [ADR-0004](0004-day-bucketed-rating-wire-shape.md)** (which pinned the response). It is a **serialization + validation** contract, not new design: the *fields* were decided in ADR-0002 and the personalization grill; this records how they are encoded on the wire and what is rejected.

```json
POST /api/v1/rating
Content-Type: application/json

{
  "lat": 25.1627,
  "lon": 55.2077,
  "activities": [
    {
      "id": "9f3a0c1e-…",
      "label": "Stargazing",
      "displayMetrics": ["temp", "cloudCover", "humidity"],
      "thresholds": {
        "temp":       { "min": 10, "max": 30, "required": true },
        "cloudCover": { "max": 20, "required": true }
      },
      "window": { "startHour": 22, "endHour": 2 }
    }
  ]
}
```

## Decisions, pinned

1. **Envelope — `{ lat, lon, activities }`, all in the body.** `lat`/`lon` move out of the query string into the JSON body: a `POST` has a body, and splitting inputs across query + body is split-brained. **No body-level version field** — the URL (`/api/v1/`) is the single version axis; a contract break bumps to `/v2/`. **No `timezone` in the request** — the forecast location's IANA zone is resolved *server-side* from `lat`/`lon` via the provider ([ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md)) and returned in the response; the client supplies only raw `lat`/`lon` and does **zero** timezone arithmetic. `lat`/`lon` is the **seed** of the server-side time-boundary chain — the client cannot pre-resolve the zone without duplicating that boundary.

2. **Per-activity identity — client-authored `id`, echoed verbatim as `activityId`.** The engine holds no activity list (ADR-0002), so request↔response correlation **must** originate client-side. `id` is a client-generated stable string, **unique within the request**, echoed unchanged into the response's `activityId`; it also doubles as the key the #6c push store uses. `label` is required, non-empty, echoed — the server needs it to compose the Window Watch push, and ADR-0004's response already carries it.

3. **`displayMetrics` is the parent (render superset); `thresholds` is the evaluated subset.** `displayMetrics` is an **ordered array** that owns both render order *and* "show-but-don't-judge" metrics (a metric on the card that does not affect the rating — e.g. humidity shown but unconstrained). `thresholds` is a **keyed map** (the incumbent shape; the engine's `Object.entries(thresholds)` is unchanged) holding only the metrics that are *evaluated*. The binding invariant: **`thresholds.keys ⊆ displayMetrics`** — you cannot evaluate a metric you do not display. This is *not* redundant duplication: the gap between the two sets *is* the show-but-don't-judge feature, and the only inconsistent state (a threshold on an undisplayed metric) is illegal and rejected (§5). `displayMetrics` is **user-chosen**, replacing ADR-0002's backend-decided list, and is echoed into the response.

4. **Per-metric threshold value shape — verbatim from the shipped engine.**
   - **Numeric:** `{ "min": n, "max": n, "required": bool }` — either bound omittable, but **at least one bound is mandatory** (a bound-less numeric threshold passes trivially and is a worse spelling of show-but-don't-judge).
   - **Flag:** `{ "type": "flag", "forbidTrue": true, "required": bool }`.
   - **`required` is mandatory** on every threshold — never defaulted. "Must-have vs nice-to-have" is the single most consequential bit of a threshold (it decides Bad vs Good); silently defaulting a forgotten field to `false` would turn an authoring slip into a falsely-passing activity.
   - **`requireTrue` is rejected** in v1 (the planned inverse flag is [Issue #8](../issues/current/implement-spec-issue-8-require-true-threshold.md), unbuilt — no wire surface reserved for unbuilt behaviour).

5. **Time-of-day `window` — optional, half-open, integer *local* hours; the client sends raw wall-clock, the server converts.** `window: { startHour, endHour }`, integers `0..23` in the **forecast location's local time** (sub-hour precision is meaningless against hourly forecast data). Semantics are **half-open `[startHour, endHour)`**, matching the engine's existing output window (`endIndex` exclusive, `duration === end − start`) — so `duration = endHour − startHour` falls out (in the same-day case; the wrap case crosses midnight and is offset to global indices by the engine) and the whole contract is half-open everywhere. The client performs **no** timezone math: the server's time-boundary module tags each hour with an internal `localHour`, and the engine compares integers, staying timezone-agnostic ([ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md)). The three cases make the encoding total:
   - **absent `window`** → evaluate the whole day *(contractually valid; superseded as a client behavior — the range-first client authors every Activity with a **Range** and never sends this case; kept for other callers and the deferred surprise feature)*;
   - **`startHour < endHour`** → same-day window;
   - **`startHour > endHour`** → **midnight-wrap** (nocturnal); the wrap is the *only* nocturnal signal (no `isNocturnal` field — a sent flag invites the contradiction `isNocturnal:false` + `endHour<startHour`), and it licenses the wrap-gated **night-stitch** recorded as an amendment to [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md);
   - **`startHour === endHour`** → **400** (the empty set under half-open; whole-day is already expressed by *omitting* `window`).

   The old `window: { startIndex, endIndex }` UTC-index encoding (grill Q2(b)) is **superseded**: it predates the 7-day day-bucketed model and a single global index-pair cannot express "2–4pm *every* day" across buckets, nor a recurring night.

6. **Validation — atomic, structured, 400.** All body-validation failures map to **`400`** (the 502/500 mapping of ADR-0004 is unchanged). Validation is **all-or-nothing** (SQLite-transaction semantics): a single invalid activity rejects the **whole** request — no partial evaluation — so the success shape (ADR-0004's `activities[].days[]`) never carries error state. Errors return a **structured array**, uniform across all error responses so the iOS decoder parses one shape (502/500 become single-element arrays):
   ```json
   { "errors": [ { "path": "activities[2].thresholds.temp", "message": "min greater than max" } ] }
   ```
   The rejection set: missing/out-of-range `lat`/`lon`; empty `activities`; missing/empty `label`; missing or **within-request-duplicate** `id`; empty `displayMetrics`; **`thresholds.keys ⊄ displayMetrics`**; an **unknown or coming-soon metric key**; numeric `min > max`; a bound-less numeric threshold; a missing `required`; a present `requireTrue`; non-integer or out-of-`0..23` `startHour`/`endHour`; `startHour === endHour`; and `activities.length` over a hard **abuse ceiling (~50)**.

   **Transport-level parse failures share the envelope.** Before validation runs, `express.json()` can reject the body outright: malformed JSON → **`400`** and an over-limit body → **`413`**. Both are mapped (in `src/server.js`) into the same `{ "errors": [ { "message } ] }` shape (single-element, no `path`) so the decoder never sees Express's default HTML error page.

   **The coming-soon rule is the load-bearing one:** a threshold on a metric whose data is not live (`darkness`, marine fields before their adapter lands) would pass trivially against placeholder data → a **silent false Perfect** — the exact hazard the whole system guards against. The backend knows which metrics are live (it owns the adapters) and **hard-rejects** any threshold on a non-available or unknown metric. This is defence-in-depth: coming-soon metrics are also **unclickable in the authoring UI** (ADR-0002), so a well-behaved client never sends one; the 400 is the backstop.

Chosen because this is the minimal body that lets a stateless, activity-agnostic engine evaluate caller-authored profiles while making the false-Perfect hazard *unrepresentable* (coming-soon reject), keeping all timezone reasoning at the server boundary (raw `lat`/`lon` + local-hour window, no client tz math), and reusing the shipped threshold shape (zero engine churn — `thresholds` stays a map).

Rejected alternatives: an **ordered `thresholds` array** with server-*derived* `displayMetrics` (one source of truth, but kills show-but-don't-judge and forces a no-op-threshold hack, plus engine churn and duplicate-key validation — the display/threshold split carries real, non-redundant information); **`lat`/`lon` kept in the query string** alongside a body (split-brained envelope); a **client-converted UTC-index window** (the superseded grill Q2(b) — pushes tz math onto the client the time-boundary module exists to own, and cannot express recurring or nocturnal windows); an **explicit `isNocturnal`/`wrapsMidnight` flag** (derivable from `endHour < startHour`; a separate field only adds a contradiction surface); a **single-string error body** (a POST with N activities × M thresholds has too large a validation surface for first-error-wins; the structured array lets an atomic-rejected client fix everything and resubmit once); **partial evaluation** of the valid activities (mixes results and errors in one response — the muddy shape the ADR-0004 audit removed); **server-side tier/quantity enforcement** (the 3-free/unlimited-Pro cap is client-enforced per grill Q3 — the backend stays stateless; the abuse ceiling is a DoS guard, *not* a tier gate).

**Consequences:** the route flips `GET → POST` and `evaluateAll(hours) → evaluateAll(hours, activities)` (Phase 2 of the rebuild). `displayMetrics` becomes a request field echoed through, not a backend constant. The iOS encoder mirrors this body and pre-validates against the served metric catalog (`GET /api/v1/metrics`) so 400s are rare. The route's existing param-validation tests rework from query-string to body, and the golden snapshot gains request-shape coverage. The wrap-gated night-stitch this schema *enables* (case `startHour > endHour`) is specified in the [ADR-0003](0003-seven-day-horizon-flat-hours-day-buckets.md) amendment, not here — this ADR owns only encoding + validation; evaluation semantics stay in ADR-0003.

Recorded because this is the contract the iOS #5a encoder serializes against (reversible only with a versioned bump), it is the single gate on the Phase-2 `GET→POST` flip, and a future reader will ask why `displayMetrics` and `thresholds` both exist (they are superset/subset, not duplicates), why the window is raw local hours rather than indices, and why a coming-soon metric is a hard 400 rather than a silently-dropped threshold.
