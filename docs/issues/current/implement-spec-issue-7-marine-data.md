# Implementation spec — Issue #7: Wire real marine data from Meteosource adapter

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #3 (Backend Internals)](implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — adapter pattern must be in place first
> Blocked by: Meteosource API tier investigation (see Section 1)

---

## 1. Context

`parse.js` currently hardcodes the following fields to placeholder values because the
Meteosource adapter does not yet extract them:

| Field         | Placeholder | Source needed                          |
|---------------|-------------|----------------------------------------|
| `douglasScale`| `0`         | Meteosource marine data (tier TBD)     |
| `swellHeight` | `0`         | Meteosource marine data (tier TBD)     |
| `swellLength` | `0`         | Meteosource marine data (tier TBD)     |
| `seaWarning`  | `false`     | UAE maritime authority API (not Meteosource) |
| `darkness`    | `0`         | Astronomy data source (not Meteosource)|
| `tide`        | `0`         | Separate tidal API — no source identified |

Until these are wired, fishing activity ratings (`boat-fishing-pro`, `boat-fishing-lite`,
`shore-fishing`) evaluate only temperature. All marine thresholds trivially pass.

---

## 2. Pre-implementation investigation required

Before writing any code, verify:

1. **Meteosource tier** — does the current API key return wave/marine fields in the hourly
   response? Fetch a live response and inspect the raw JSON for fields like `wave_height`,
   `wave_period`, `swell_height`, `sea_state`, or equivalent.
2. **Free vs paid tier split** — the Lite/Pro boundary in `fishing.js` is already settled
   (resolved in Issue #3): `boatFishingLite` uses `windSpeed` (free-tier proxy); `boatFishingPro`
   uses `douglasScale` and `swellHeight` (premium). The remaining question is purely whether
   Meteosource actually returns those marine fields on the Pro subscription — confirm against
   a live response and update `CONTEXT.md` if the tier mapping differs from what is documented.
3. **Douglas scale mapping** — Meteosource may not use the Douglas scale directly. If it
   returns wave height in metres, a conversion function is needed (see Douglas scale table
   in the `fishing.js` comments).
4. **`seaWarning` and `darkness`** — these require APIs outside Meteosource. Identify and
   evaluate candidate sources before scoping the work. Do not implement until a source is
   confirmed.
5. **`tide`** — no tidal data source has been identified. Keep deferred.

---

## 3. Out of scope

- `tide` — deferred indefinitely; no data source identified.
- `seaWarning` — deferred until a UAE maritime authority API is identified.
- `darkness` — deferred until an astronomy data source is integrated (see `starGazingPro`
  deferral in Issue #3).
- Any changes to activity threshold values — those are fixed in Issue #3.
- HTTP API or iOS changes — the field values will flow through automatically once the
  adapter populates them.

---

## 4. Changes (to be detailed after investigation)

### 4.1 `src/weather/adapters/meteosource.js`

Add extractor functions for whichever fields the Meteosource API actually provides.
Follow the existing adapter pattern — one function per field, raw response → normalised value.

### 4.2 `src/weather/parse.js`

Replace the placeholder `0` values for confirmed fields with `adapter.<field>(row)` calls.
Remove the `// PENDING Issue #7` comments for any field that is now wired.
Leave placeholders and comments in place for any field that remains unresolved.

### 4.3 `src/activities/fishing.js`

Once `douglasScale` and `swellHeight` are wired with real data, add them back to the affected activities' `displayMetrics`:

```js
shoreFishing.displayMetrics:   ["temp", "windSpeed", "douglasScale"]
boatFishingPro.displayMetrics: ["temp", "douglasScale", "swellHeight"]
```

These fields were deliberately omitted from `displayMetrics` in Issue #3 because `parse.js` hardcodes them to `0` — displaying a hardcoded zero on the iOS card would be misleading. Once real data flows through the adapter, the fields are meaningful and should be surfaced.

`seaWarning` (`boatFishingPro`, `boatFishingLite`) and `darkness` (`starGazingLite`) were omitted for the same reason but are sourced from different APIs (UAE maritime authority and astronomy data, respectively) — they will be re-added when those data sources are integrated, not by this issue.

---

## 5. Related artifacts

- [`CONTEXT.md`](../../CONTEXT.md) — domain glossary.
- [Issue #3 (Backend Internals)](implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — established
  the adapter pattern and placeholder fields this issue fills in.
