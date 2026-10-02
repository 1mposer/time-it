# Implementation spec 04 — the Jev concerns layer ("Jev to be the layer that speaks the practitioner's language")

> **DEFERRED (scoped 2026-10-02, owner session).** Supersedes the 2026-09-30 "Weather-analysis surface" row (generative synthesis behind `POST /api/v1/analysis`) — that framing is withdrawn; this file is the home. Promote condition and preconditions: [ROADMAP §Deferred](../ROADMAP.md). Nothing here is built; nothing here touches the live path until its ADR is accepted. Origin: the `experiment/jev-ios-test-triage` branch, where Jev (TypeSafe System One, `@typesafe-ai/sdk` 0.6.0 — pinned, security-vetted) triaged the iOS test suite and taught the state / questions / composition decomposition reused below.

> Work order shape for a future implementing agent. Read this file, then its ADR (to be written — wins over this file), then `CLAUDE.md`. Written 2026-10-02 from an owner conversation; every **owner ruling** is marked as such, everything else is the agent's recommendation and may be re-cut by the ADR.

## 1. Goal

The threshold engine judges what a sensor measures. Practitioners think in their own vocabulary: a golfer thinks headwind, crosswind, dew sweepers, the 10-degree rule — not "wind speed 18". This layer lets the product speak that vocabulary. For each **concern set** (golf, kitesurfing, stargazing…) a curated list of **concerns** is phrased the way the activity's community phrases it and asked of Jev as a typed question over **enriched** hourly forecast JSON. The answers are probabilities the client renders on a new tab of the activity detail page (widget form: out of scope here, Figma-gated per [ADR-0008](../../adr/0008-figma-first-ui-gate.md)).

**Owner rulings (2026-10-02):**
- Concerns are **built into the app** — authored by the owner/agents, never by end users. The user authors thresholds (preferences); the product ships concerns (domain knowledge).
- Concerns are a **server-side catalog, not part of the Activity object**. Same mould as the metric catalog: the server knows which concern sets exist; the client references a set by id; the user's Activity stays client-owned, so [ADR-0002](../../adr/0002-activity-agnostic-engine.md) holds. The ADR must say this explicitly (the 2026-09-30 row's open point).
- **Enrichment is deterministic code, before Jev.** Derived weather facts are computed from the fetched metrics, unit-tested, and added to the JSON Jev reads. Jev judges described situations; it never does the arithmetic.
- **Jev runs server-side on the weather-cache fill**, cached under the same key (lat/lon at 2 dp) and TTL (60 min — the owner-confirmed Meteosource cadence, [README](../../API_documentation/meteosource/README.md)); results ship to the client. One Jev request per location cell per hour per referenced concern set. No second cache; no polling tighter than the weather cache.
- **Judgments are per hour, aggregated in code** to the Activity's Range per day (the ADR-0011 pattern: hour → window mean → day). Pilot concern set: **golf**.

**Agent recommendation, to be ruled in the ADR:** the pilot is **display-only** — concern judgments feed neither `rating` nor `score` (the 2026-09-30 row's "never feeds ratings" posture; folding them into the day score would amend [ADR-0011](../../adr/0011-day-score.md) and should be its own later decision with real usage behind it).

## 2. Terms (candidates for CONTEXT.md once the ADR lands — not added before)

- **Concern** — one thing practitioners of an activity care about, phrased in their words, answerable from the hourly weather. Backed by exactly one Jev question (Score, Noul or Choice) and the enriched fields it reads.
- **Concern set** — the curated list of Concerns for one activity family, keyed by id (`golf`). Lives in the server catalog. An Activity may reference at most one.
- **Enrichment** — deterministic derivations over the fetched hourly metrics (dew-point spread, gust ratio, hours since sunrise, temp delta vs the same hour yesterday…). Internal; exposes nothing new on the wire by itself.
- **Judgment** — Jev's typed answer for one Concern on one hour: a Score's expected level + probabilities + confidence, a Noul's probability, or a Choice's option + probabilities.

## 3. Architecture — four layers, each testable alone, in build order

```
src/weather/adapters/meteosource.js   + wind.angle, wind.gusts, dew_point, pressure, feels_like, daily astro sunrise/sunset   (adapter gap — see §4)
src/weather/enrich.js                 enrichHours(hours, { sun })  → hours + derived fields                 (pure; layer 1)
src/concerns/catalog.js               CONCERN_SETS, isKnownConcernSet, questionsFor(setId)                   (layer 2 — metricCatalog mould)
src/concerns/judge.js                 createConcernJudge({ client, now }) → judge(enrichedHours, setIds)     (layer 3 — Jev seam; SDK imported nowhere else)
src/services/weatherCache.js          cache entry gains judgments per referenced set, same key + TTL         (layer 3 wiring)
src/routes/rating.js                  additive wire block; per-activity day aggregation in code              (layer 4)
```

Layer 1 has no dependency on anything else and surfaces the adapter gaps immediately — build it first. Layer 3 is the only place `@typesafe-ai/sdk` is imported (the `apns.js` precedent: provider specifics stop at the seam).

## 4. Pilot concern set — golf (draft questions; the authoring workbench §8 tunes the wording)

The four concerns the owner named, and what each needs:

| concern | primitive | reads | status |
|---|---|---|---|
| **10-degree rule** — carry distance lost to cold air (≈2 yd per 10 °F drop; air density) | Score, 4 levels from "full carry" to "club up twice" | `temp`, `humidity`, `pressure` (air density derived in enrichment) | fetchable today except `pressure` (adapter add) |
| **Dew sweepers** — early tee times on wet greens | Noul, gated in code to hours within ~2h after sunrise | `dew_point` spread, `humidity`, `rainFall` overnight, hours since sunrise | needs `dew_point` + daily sunrise (adapter add) |
| **Headwind** | Score of how much the wind fights a shot | `windSpeed`, `wind.gusts`, `wind.angle` **relative to a heading** | **blocked on a reference heading** — the forecast has no hole orientation. Pilot models "wind strength and gust variability as a golfer feels it" (speed + gust ratio); the direction-relative decomposition waits for a heading input (course / user). The ADR must say whether the pilot ships head/crosswind as this proxy or omits them |
| **Crosswind** | Score, same shape | same as headwind | same block |

Every question follows the rules the test-triage experiment proved out: one dimension per question; Score levels describe **situations, not degrees**; a `none`/no-match outcome whenever nothing may fit; the state names the relevant enriched fields so Jev never computes them. Questions for a set run in **one** `systemOne` call over the whole hour array (they are independent and parallel), state shaped as `{ location_context, hours: [...] }` with the enriched fields present and the raw placeholders (`douglasScale` etc., coming-soon metrics) **stripped** — a Concern may only read live metrics, the metric catalog's false-Perfect rule applied to concerns.

**Adapter additions (gap found 2026-10-02):** the standard tier's hourly payload carries `wind.angle`, `wind.dir`, `wind.gusts`, `dew_point`, `feels_like`, `pressure`, `cape` (per the OpenAPI export) and the daily section carries sun rise/set; the adapter extracts none of them today. They become **internal enrichment inputs first**; whether any is promoted to a live wire metric (and so becomes thresholdable) is a separate metric-catalog decision, not part of this spec.

## 5. Hard constraints

- `validateActivities` gains **one** optional field: `concernSet: string` — must be a known catalog id (unknown → `400`, the coming-soon-metric mould). Nothing else in the request changes; an Activity without it gets no concern block. This is an [ADR-0005](../../adr/0005-custom-activity-request-schema.md) amendment, in the ADR.
- `/rating` stays stateless; `GET /health` stays DB-independent; the push jobs **ignore** concerns entirely (digest and detector copy are verdict-driven and unchanged).
- Jev failure **degrades, never 502s**: a typed `ConcernJudgeError` leaves the weather entry cached and the concern block `null` with the rest of the response intact. The rating route's `502` stays exclusively `UpstreamError` (weather).
- Key stays server-side (`TYPESAFE_API_KEY`, Railway env; `.env.example` entry). The seam builds its client lazily on first use — a deploy without the key serves ratings with concerns `null`, loudly `console.warn`ed once.
- No per-user data reaches TypeSafe: state is the enriched hours for a 2-dp location cell plus the cell's IANA zone; **no coordinates, no device id, no Activity labels**. The ADR records this against [ADR-0010](../../adr/0010-data-retention-privacy-posture.md) §"shared with third parties: never" — weather for a coarse cell is not user data, but the ADR must rule it, not this file.
- Independence rule: judgments never feed `rating`, `score`, the digest, or the detector (pilot — §1).
- Cost guard: at most N concern sets per cache fill (N small, catalog-sized); the per-request abuse ceiling (~50 activities) already bounds the referenced-set count.

## 6. Wire shape (draft — the ADR settles it; additive, iOS decoder must treat absence as "no concerns")

Judgments are location-level (per cell, per hour), aggregation is per Activity (its Range). So the response carries each referenced set **once** and each Activity's day aggregates beside its `days[]`:

```json
{
  "forecastStart": "…", "timezone": "…",
  "activities": [{ "activityId": "…", "label": "…", "displayMetrics": […], "days": […],
                   "concernSet": "golf",
                   "concerns": [ { "id": "ten_degree_rule", "days": [ { "dayIndex": 0, "level": 1.2, "confidence": 0.8 }, … ] } ] }],
  "concernSets": { "golf": { "concerns": [ { "id": "ten_degree_rule", "label": "10-degree rule", "kind": "score",
                                             "legend": ["Full carry", "…"], "hours": [ { "level": 1.1, "confidence": 0.9 }, … ] } ] } },
  "hours": […]
}
```

- `concernSets.<id>.concerns[].hours` is aligned with the top-level `hours[]` by index (same length, `null` entry where Jev had no answer). `activities[].concerns[].days[]` is the mean over that Activity's Range hours in the day bucket (same bucket slice the rating used; `null` when the bucket has zero window hours — the ADR-0011 null rule reused). A Noul concern aggregates its probability; a Choice concern ships the modal option and its probability.
- Both blocks are **absent** when no Activity references a set, and `null`-valued when the judge failed (§5).

## 7. Tests (TDD per layer; no live TypeSafe calls in the suite — the judge is a factory with an injected client, the fake weather provider's twin)

- `tests/weather/enrich.test.js` — every derived field hand-computed (dew-point spread, gust ratio, hours-since-sunrise across midnight and across the zone's DST-free offset, temp delta vs yesterday when yesterday is outside the horizon → `null`), absent inputs → `null` never `NaN`.
- `tests/weather/adapter.test.js` — the new extractions, each `?? null`.
- `tests/concerns/catalog.test.js` — every set has unique concern ids, every concern names only live/enriched fields, every Score has 2..10 situation-described levels, `isKnownConcernSet`.
- `tests/concerns/judge.test.js` — fake client: one `systemOne` call per set; answer → judgment mapping for all three primitives; `ConcernJudgeError` on SDK errors; placeholders stripped from state; no coordinates in state (pin it).
- `tests/services/weatherCache.test.js` — an entry's judgments share the weather TTL; a judge failure caches the weather and not the failure; two sets referenced → one call each.
- `tests/routes/validateRatingRequest.test.js` — `concernSet` unknown → structured `400`; absent → valid.
- `tests/server/rating.test.js` — golden snapshot with and without a referenced set; day aggregation over a nocturnal Range; judge failure → `null` blocks + `200`.
- A **shared worked-example fixture** `tests/fixtures/concern-aggregation-examples.json` if the iOS side ever mirrors the aggregation ([ADR-0007](../../adr/0007-client-side-mirrors.md)); the recommendation is that it does not — the client renders, the server aggregates.

## 8. The authoring workbench (internal tool, not shipped; after layer 3 exists)

A local page + the dev-only proxy (key stays server-side) that: picks a concern set, pulls a real cached forecast through enrichment, runs the set, shows per-hour distributions and confidence per concern, and lets the owner edit instructions / criteria and re-run live on a **pinned example forecast** so wording changes compare like-for-like. Hand-labelled hours (the owner's own "this is a dew-sweeper morning") become the calibration set the page scores wording against. This is where every quality gain in the test-triage experiment came from (criteria wording; what context the state carries) — so it is the tool, not a nicety. Scope and stack: decided when promoted.

## 9. Preconditions (all before any code on the live path)

1. **ADR-0012 (working title: concern catalog + Jev seam)** — squares the server-side catalog with ADR-0002, amends ADR-0005 (`concernSet`), rules the ADR-0010 third-party point (§5), fixes the wire shape (§6), rules display-only vs score-feeding (§1), and the head/crosswind heading question (§4).
2. Figma frames for the detail-page concerns tab ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)) — the widget form the owner parked 2026-10-02.
3. `TYPESAFE_API_KEY` in Railway; SDK actually installed (it is pinned in `package.json` but not yet a runtime import anywhere).

## 10. Done means (when promoted)

`npm test` green with every §7 box; a live Dubai rating with `concernSet: "golf"` returns the §6 blocks for the four pilot concerns (or the ADR-reduced set); the same request with the key removed returns `200` with `null` blocks; CLAUDE.md swept in the same commit (architecture table, wire contract, tests map, env vars); CONTEXT.md gains the §2 terms. Commit prefix `feat(concerns):`.
