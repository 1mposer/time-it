# Issue #10 — Pre-5a hardening: bugs, incoherences, and test gaps

> ✅ **COMPLETE (resolved pre-#5a; historical record — do not act on this).** Group D targets the React mockup deleted 2026-07-19; F1's `engines` gap was closed by #6b. Current truth: `CLAUDE.md`.

> Review context: max-effort automated review run after Issue #4 merged, before Issue #5a starts.
> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: Issues #3 and #4 complete — this is hardening of those, not new features.
> Required by: Issue #5a — iOS client depends on a contract the server actually honours.

This file is a grilling brief. Every section is a problem to resolve. The agent reading this should ask the developer to confirm the fix decision before touching any code. Do not batch decisions — resolve one finding at a time.

---

## How to use this doc

Each finding has:
- **What**: the exact bug or gap
- **File + line**: where the code lives
- **Risk**: what actually breaks
- **Fix options**: choices to pick from — confirm which before implementing

---

## Group A — Crashes in the weather adapter (highest priority)

These all crash `parseWeather` on certain Meteosource responses and surface as 500s. Fix as a batch since they're all in `src/weather/adapters/meteosource.js`.

---

### A1 — `h.wind.speed` throws TypeError when wind object is absent

**File:** `src/weather/adapters/meteosource.js:8`

```js
windSpeed: (h) => h.wind.speed,
```

**Risk:** If Meteosource returns a row where `wind` is null or absent (data gap, calm-conditions tier), `h.wind.speed` throws `TypeError: Cannot read properties of null`. This crashes all 24 hours, the whole request fails as 500.

**Fix options:**
- A. Optional chain: `h.wind?.speed ?? 0` — returns 0 when absent, request survives
- B. Optional chain: `h.wind?.speed ?? null` — returns null, threshold check must handle null (same as undefined issue in A3)
- C. Throw a typed `UpstreamError` — propagates as 502 not 500

*Grilling question: what should the fallback value be when wind is absent? 0 (calm) or null (unknown)?*

---

### A2 — `h.precipitation.total` throws TypeError when precipitation is absent

**File:** `src/weather/adapters/meteosource.js:9`

```js
rainFall: (h) => h.precipitation.total,
```

**Risk:** Same crash path as A1. `h.precipitation.total` throws if `precipitation` is null.

**Fix options:**
- A. `h.precipitation?.total ?? 0`
- B. `h.precipitation?.total ?? null`

*Grilling question: same as A1 — rainFall is not currently evaluated by any threshold, so default 0 is safe here. Confirm?*

---

### A3 — `cloudCover` fallback returns the whole object when `.total` is absent

**File:** `src/weather/adapters/meteosource.js:10`

```js
cloudCover: (h) => h.cloud_cover?.total ?? h.cloud_cover,
```

**Risk:** If `h.cloud_cover` is an object WITHOUT a `.total` key, the `??` operator returns the entire `h.cloud_cover` object (not a number). Downstream, `hourData.cloudCover` is a plain object. The `cloudCover: { max: 20, required: true }` threshold on `stargazing-lite` then does `object > 20` → NaN comparison → silently passes. This means stargazing always looks clear even when it's cloudy.

**Fix options:**
- A. `h.cloud_cover?.total ?? 0`
- B. `h.cloud_cover?.total ?? null`

*Grilling question: should an unknown cloudCover default to 0 (clear sky) or fail safe with null? Stargazing requires it. If we don't know, failing is safer than assuming clear.*

---

### A4 — `h.date.split("T")` throws on non-ISO-8601 date strings

**File:** `src/weather/adapters/meteosource.js:5`

```js
hour: (h) => parseInt(h.date.split("T")[1].split(":")[0], 10),
```

**Risk:** If Meteosource returns a space-separated date (`"2026-06-10 14:00"` instead of `"2026-06-10T14:00"`), `split("T")[1]` is `undefined`, and `.split(":")` on undefined throws. Crashes the entire parse.

**Fix options:**
- A. Defensive: `(h.date.includes("T") ? h.date.split("T")[1] : h.date.split(" ")[1]).split(":")[0]`
- B. Use Date parsing: `new Date(h.date).getUTCHours()`
- C. Assert format and throw a clear error

*Grilling question: have you seen Meteosource return non-T-separated dates? If not, option C (assert + throw) is safer than silently tolerating a format change.*

---

### A5 — `allHours[0]` accessed without a length guard in parse.js

**File:** `src/weather/parse.js:6`

```js
const forecastStart = adapter.forecastStart(allHours[0]);
```

**Risk:** If Meteosource returns `{ hourly: { data: [] } }` (malformed response, API outage, free-tier cap hit), `allHours[0]` is `undefined`. `adapter.forecastStart(undefined)` calls `undefined.date`, throwing `TypeError`. This does NOT match the `"Response status"` or `"fetch"` error classifier in `rating.js`, so it surfaces as a 500 not a 502 — misleading.

**Fix options:**
- A. Guard: `if (!allHours.length) throw new Error("Response status: empty forecast")` — reuses 502 classifier
- B. Guard: `if (!allHours.length) throw new UpstreamError("Empty forecast from provider")` — requires typed error (see B3)
- C. Guard with fallback `forecastStart`: return `{ forecastStart: null, hours: [] }` — caller must handle empty

*Grilling question: is an empty hours array from the server a valid response, or always a provider failure?*

---

## Group B — Silent data and contract bugs

---

### B1 — `API_KEY` undefined serialises as the literal string `"undefined"` in the URL

**File:** `src/weather/index.js:13`

**Confirmed by:** `node -e "console.log(new URLSearchParams({key:undefined}).toString())"` → `key=undefined`

**Risk:** When `process.env.API_KEY` is not set (missing `.env`, CI without secrets, fresh deploy), every request sends `?key=undefined` to Meteosource. Meteosource returns a 401/403. The route catches it as a 502 ("Weather data unavailable") with no indication the real cause is a missing environment variable. Developer time is wasted debugging.

**Fix options:**
- A. Guard at startup: in `app.js`, throw if `!process.env.API_KEY`
- B. Guard in `getWeather`: throw a clear `Error("API_KEY environment variable is not set")` before building params
- C. Guard in `fetch.js`: validate params before building the URL

*Grilling question: should a missing API key crash the server at startup (fail-fast) or fail at request time?*

---

### B2 — `undefined` metric value in hourData silently passes threshold checks

**File:** `src/decision/decision_engine.js:4`

```js
if (config.min !== undefined && value < config.min) return false;
if (config.max !== undefined && value > config.max) return false;
```

**Risk:** If `hourData[metric]` is `undefined` (metric key absent from the hour object), JavaScript computes `undefined < number` as `NaN < number` which is `false`. The threshold check returns `true` — a missing field silently passes as if within range. Same for flag thresholds: `undefined === true` is `false`, so a forbidTrue field passes when the data is absent.

This is latent right now because `parse.js` always sets every field. It becomes active when a new activity is added with a threshold field that `parse.js` does not yet emit, or when a partial adapter response omits a field.

**Fix options:**
- A. Add to `checkThreshold`: `if (value === undefined || value === null) return false` — absent data always fails
- B. Add to `checkThreshold`: guard only required fields — `if ((value === undefined || value === null) && config.required) return false`
- C. Add a schema-level validation in `parseWeather` that throws if any expected field is absent

*Grilling question: should a missing metric fail the hour as "bad" or be treated as "unknown" (neutral/skip)? Marine fields are intentionally absent until Issue #7 — those have placeholder 0 values in parse.js, so this guard won't affect them.*

---

### B3 — 502 error classifier catches TypeErrors that mention "fetch" — masks runtime bugs

**File:** `src/routes/rating.js:19`

```js
if (err.message?.includes('Response status') || err.message?.includes('fetch')) {
  return res.status(502).json({ error: 'Weather data unavailable' });
}
```

**Risk:** `TypeError: fetch is not defined` (Node < 18) contains the string "fetch". `ReferenceError: fetch is not defined` same. Any internal coding error whose message happens to mention "fetch" silently becomes a 502 to the client, hiding the real bug. Also, network failures like `ENOTFOUND` and `ETIMEDOUT` do NOT contain either string — they'd become 500s even though they're provider failures.

**Fix options:**
- A. Replace string matching with a typed error: create `class UpstreamError extends Error {}` in `src/weather/fetch.js`, throw it on non-ok responses and network failures, catch by type in `rating.js`
- B. Add more patterns: include `ENOTFOUND`, `ETIMEDOUT`, `ECONNREFUSED`
- C. Leave as-is until Issue #6 deployment makes it matter

*Grilling question: are you OK with a network timeout to Meteosource appearing as a 500 to the iOS client? If not, fix A is the right level.*

---

### B4 — `forecastStart` has no timezone designator — iOS assumes UTC, but Meteosource may shift it

**File:** `src/weather/adapters/meteosource.js:4` + `src/routes/rating.js:8`

Meteosource returns dates like `"2026-06-10T14:00:00"` — no `Z`, no `+00:00`. When `timezone` is `"UTC"` (the default) this is fine. But when a non-UTC timezone is passed (e.g. `timezone=Asia/Dubai`), Meteosource may shift the `date` field to local time. The iOS spec says `forecastStart` is UTC and uses it to compute clock times (`forecastStart + index * 1 hour`). If `forecastStart` is actually local time, every computed clock time is off by the UTC offset.

**Fix options:**
- A. In `getWeather`, always force `timezone: "UTC"` regardless of what the caller passes, drop the timezone param from the route entirely
- B. In `getWeather`, append `Z` to forecastStart only when timezone is UTC: `return forecastStart + (timezone === 'UTC' ? 'Z' : '')`
- C. Document the contract and make it the iOS app's responsibility

*Grilling question: does the iOS app currently use the `timezone` query param at all? If the iOS app always passes UTC or never passes timezone, option A (hard-code UTC) is the simplest fix.*

---

## Group C — CLI tool is wrong (cli.js)

---

### C1 — `cli.js` sampleUserPrefs missing `dustAlert` threshold

**File:** `cli.js:7`

```js
const sampleUserPrefs = {
  activityId: "volleyball",
  thresholds: {
    temp:      { min: 15, max: 35, required: true },
    humidity:  { max: 60,          required: true },
    windSpeed: { max: 15,          required: false },
    uV:        { max: 6,           required: false },
  },
};
```

The real `volleyball` activity definition in `volleyBall.js` includes `dustAlert: { forbidTrue: true, type: "flag", required: true }`. The CLI omits it. When Meteosource returns a sandstorm hour (`dustAlert: true`), the CLI rates it "perfect" while the server rates it "null". The CLI is not a faithful preview of production.

**Fix options:**
- A. Import the real activity by id from `src/activities/index.js` instead of hardcoding thresholds
- B. Manually add `dustAlert: { forbidTrue: true, type: "flag", required: true }` to the CLI prefs

*Grilling question: should cli.js preview a single specific activity (option A — always current) or stay as a standalone test fixture?*

---

### C2 — `cli.js` discards `forecastStart` from `parseWeather` return

**File:** `cli.js:29`

```js
const { hours } = parseWeather(raw, meteosourceAdapter);
```

`forecastStart` is destructured away. The printed JSON has `startIndex: 3` but no `forecastStart`, so a developer can't derive the actual clock time of the window from the CLI output.

**Fix options:**
- A. Destructure both: `const { forecastStart, hours } = parseWeather(...)` and include `forecastStart` in the console output
- B. Leave as-is if CLI is just for engine testing, not for time-range preview

---

## Group D — Frontend/backend incoherence (ios/ mockup)

These affect the React/Vite mockup at `ios/`. They need to be resolved before the SwiftUI implementation (Issue #5a) so the design mockup doesn't mislead the agent.

---

### D1 — `ActivityCard.tsx` uses `condition: 'none'` but backend sends `rating: null`

**File:** `ios/src/app/components/ActivityCard.tsx`

The TypeScript interface has `condition: 'perfect' | 'good' | 'none'`. The real API sends `"rating": null` (JSON null) for no-window activities. When the SwiftUI agent reads the mockup as a design reference, it will see `'none'` as the no-window state. But the Swift model must decode `null` from JSON.

**Fix options:**
- A. Update the mockup interface to `rating: 'perfect' | 'good' | null` to match the actual API field name and type
- B. Leave mockup as-is and document the mapping in `design-decisions-issue-5.md`

*Grilling question: should the mockup be kept as a visual prototype only (option B), or kept as a structural reference that matches the API contract exactly (option A)?*

---

### D2 — `ActivityCard.tsx` uses `bestTimeStart`/`bestTimeEnd` but backend sends `startIndex`/`endIndex`

**File:** `ios/src/app/components/ActivityCard.tsx`

The mockup Activity type uses `bestTimeStart: number` and `bestTimeEnd: number` as clock hours (e.g. `6`, `14`) to position a timeline bar. The real API sends `startIndex` and `endIndex` as 0-based array positions into `forecast.hours[]`. They are NOT clock hours — an `startIndex` of 0 could be 3pm depending on `forecastStart`.

The SwiftUI `DashboardViewModel` spec (Issue #5a) correctly describes converting `startIndex → clock hour` via `forecastStart`. But the mockup's timeline logic is based on clock hours directly. Any SwiftUI agent that uses the mockup timeline as the basis for `ActivityCardView` would implement the wrong mapping.

**Fix options:**
- A. Update `ios/guidelines/Guidelines.md` to clearly document this mapping: "chips and timeline use `hours[activity.startIndex]`, not a clock-hour field"
- B. Also update the `App.tsx` fixture data to use `startIndex`/`endIndex` instead of `bestTimeStart`/`bestTimeEnd` to keep the mockup structurally aligned

*Grilling question: the mockup is a visual reference, not a structural one — is option A (docs only) sufficient, or must the mockup code match the API contract?*

---

## Group E — Test gaps

These are missing tests that let real bugs ship silently. Rank by likelihood of a real regression going undetected.

---

### E1 — No test for `seaWarning: true` on fishing activities

**File:** `tests/decision/evaluateAll.test.js`

`dustAlert: true` is tested for volleyball but `seaWarning: true` is never tested for any fishing activity. All three fishing activities have `seaWarning: { forbidTrue: true, required: true }`. If the flag-type branch in `checkThreshold` regressed, all fishing ratings would silently become "perfect" whenever there's a sea warning.

**Fix:** Add a test: `evaluateAll(makeHours({ seaWarning: true }))` → verify all fishing activities have `rating: null`.

---

### E2 — No test exercises the "good" rating path

**File:** `tests/decision/evaluateAll.test.js` + `tests/server/rating.test.js`

`makeHours()` produces hours that pass ALL thresholds for ALL activities. So every test result is "perfect". The `goodWindow` branch in `evaluate()` and the "good" path through `evaluateAll` are completely untested. A regression in `findLongestWindow` called with "good" would ship silently.

**Fix:** Add a test where windSpeed > 15 (fails volleyball's optional windSpeed threshold) but all required thresholds pass → volleyball should rate "good" with correct startIndex/endIndex.

---

### E3 — No test confirms `startIndex`/`endIndex`/`duration` are ABSENT on null rating

**File:** `tests/server/rating.test.js:52`

The spec says these fields are OMITTED (not present, not set to null/0) when `rating` is null. The current test only checks they're PRESENT on a non-null rating. The field-absent contract is untested. If `evaluateAll` ever spread those fields with undefined values, the iOS `Codable` decoder would error on unexpected keys.

**Fix:** Inject hours that force at least one activity to `rating: null` (e.g. extreme temp), then assert `'startIndex' in activity === false`.

---

### E4 — `require.cache` injection in `rating.test.js` has no teardown

**File:** `tests/server/rating.test.js:18`

The fake `getWeather` is injected before the server loads and never removed. Currently safe because `node --test` isolates per file. Not safe if test isolation changes (e.g. `--test-isolation=none`, or a test harness that requires all files in one process).

**Fix options:**
- A. Add `after(() => delete require.cache[weatherPath])` at the end of the test file
- B. Refactor to use dependency injection in the route handler — pass `getWeather` as a param or use a service locator — so tests can swap it without cache patching
- C. Document the node --test isolation dependency with a comment in the test file

---

## Group F — Configuration gaps

---

### F1 — No `engines` field in `package.json` — Node 18+ required but unenforced

**File:** `package.json`

`fetch()` is used as a global in `src/weather/fetch.js`. It is built-in from Node 18. There is no `engines` field. Railway defaults to Node 18+, but local dev or CI on Node 16 would fail with `ReferenceError: fetch is not defined` which — due to the "fetch" string in the error message — gets misclassified as a 502.

**Fix:** Add `"engines": { "node": ">=18.0.0" }` to `package.json`.

---

### F2 — `dotenv.config()` is called inside `src/server.js` (library module side effect)

**File:** `src/server.js:1`

`server.js` is a library module — it exports the Express app and is `require()`'d by tests. A library calling `dotenv.config()` at require-time is a side effect on `process.env` that callers don't control. `app.js` already calls `dotenv.config()` before requiring `server.js`.

**Fix:** Remove the `dotenv.config()` call from `server.js`. `app.js` and `cli.js` handle it. Tests run fine because they don't need `.env` (they mock `getWeather`).

---

## Group G — Latent / design (address before Issue #7)

These are dormant now but will bite during marine data integration.

---

### G1 — All 24 hours share the same `moon` array reference

**File:** `src/weather/parse.js:16`

`moon` is constructed once before the `.map()` and the same array object is placed into every hour. Any code that pushes to `hour[n].moon` mutates all 24 hours simultaneously. Dormant now. Becomes active when astronomy data is wired.

**Fix:** Inside the map: `moon: [...moon]` — a shallow copy per hour.

---

### G2 — `findLongestWindow` tie-breaking behaviour is undocumented and untested

**File:** `src/decision/decision_engine.js:38`

When two equal-length windows exist, the first one wins (strictly `>`). The iOS app shows the earlier block. This is a deliberate choice, but it's untested — a `>=` refactor would silently change behaviour.

**Fix:** Add a test with two equal-length perfect windows and assert `startIndex` is the earlier one. Add a short comment on the `>` comparison.

---

### G3 — CORS open (`*`) is permanent — no environment gate for production

**File:** `src/server.js:7`

`cors()` with no options sets `Access-Control-Allow-Origin: *` on every response, including the Railway deployment. The iOS native app doesn't use CORS (NSURLSession), so the wildcard serves no purpose in production and exposes the Meteosource API key quota to any web caller.

**Not a pre-5a blocker.** Track for Issue #6 (deployment). Add `CORS_ORIGIN` env var support: open wildcard in dev, locked to the web dashboard origin (or disabled) in prod.

---

## Summary table

| ID  | File | Severity | Type |
|-----|------|----------|------|
| A1  | adapters/meteosource.js:8  | CRASH | null guard missing |
| A2  | adapters/meteosource.js:9  | CRASH | null guard missing |
| A3  | adapters/meteosource.js:10 | SILENT WRONG DATA | cloudCover fallback returns object |
| A4  | adapters/meteosource.js:5  | CRASH | non-ISO date throws |
| A5  | weather/parse.js:6         | CRASH → wrong HTTP status | empty hourly guard |
| B1  | weather/index.js:13        | MISLEADING 502 | API_KEY=undefined in URL |
| B2  | decision_engine.js:4       | SILENT PASS | undefined metric NaN comparison |
| B3  | routes/rating.js:19        | WRONG ERROR CLASS | 502 classifier too broad |
| B4  | adapters/meteosource.js:4  | CONTRACT BREACH | forecastStart no timezone |
| C1  | cli.js:7                   | WRONG OUTPUT | missing dustAlert in prefs |
| C2  | cli.js:29                  | DATA LOSS | forecastStart discarded |
| D1  | ActivityCard.tsx           | FRONTEND INCOHERENCE | 'none' vs null |
| D2  | ActivityCard.tsx           | FRONTEND INCOHERENCE | bestTimeStart vs startIndex |
| E1  | evaluateAll.test.js        | TEST GAP | seaWarning untested |
| E2  | evaluateAll.test.js        | TEST GAP | good rating path untested |
| E3  | rating.test.js:52          | TEST GAP | null-rating absent fields untested |
| E4  | rating.test.js:18          | LATENT | cache injection no teardown |
| F1  | package.json               | CONFIG | no engines field |
| F2  | server.js:1                | DESIGN | dotenv in library module |
| G1  | parse.js:16                | LATENT | shared moon reference |
| G2  | decision_engine.js:38      | LATENT | tie-breaking untested |
| G3  | server.js:7                | FUTURE | CORS open in production |

---

## Grilling order recommendation

Start with Group A (all are crash-risk in the adapter — fix as one batch), then B1 (API_KEY is a deploy-time gotcha), then F1 (engines field is one line), then F2 (dotenv side effect). After those are clean, address test gaps E1–E3 to lock the contract. D1 and D2 need a decision on whether the mockup is a visual-only reference or must be structurally aligned.

B2 and B3 need design decisions (fail-safe vs pass-safe, typed errors) — leave for after Group A is done.

C1 and C2 are quick fixes but low priority (CLI is dev-only).
