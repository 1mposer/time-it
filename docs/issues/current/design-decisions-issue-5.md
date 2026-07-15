# Design decisions — Issue #5 (iOS app)

> Shared visual/UX + nav reference for both sub-issues #5a and #5b, reconciled to the Phase 1/2 rebuild and the locked grill decisions. The **visual** decisions (colour, typography, layout, chip tiers) are the source of truth alongside [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md). The **contract** facts here now match the shipped backend: activities are **caller-supplied** via `POST /api/v1/rating` (no server-side list), the per-hour `hour` field was **dropped**, a result is a per-activity **`days[]`** array (not a single top-level `rating`/`startIndex`), and there are **no accounts** and **no bottom tab bar**. See [ADR-0001](../../adr/0001-no-accounts-guest-first.md) (no accounts), [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md) (response), [ADR-0005](../../adr/0005-custom-activity-request-schema.md) (request), and [STATUS.md](../../STATUS.md) §5.

> Do not relitigate these decisions. Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md).
> Build specs: [`implement-spec-issue-5a-ios-core.md`](implement-spec-issue-5a-ios-core.md) (core read-only) and #5b (authoring/Pro, to be written).

---

## Navigation and first screen

- App opens directly to the dashboard — no welcome screen, no launch gate, **no accounts** (ADR-0001).
- **No bottom tab bar** (grill Q8). The dashboard is the single root surface inside one `NavigationStack`.
- **Settings** → top-right **gear** (a sheet). **Add activity** → a ghost "add" card at the end of the list (authoring; #5b). Home is the root.

## Dashboard

- Header: ocean blue gradient (`#1253a4 → #1a78c2 → #29a8e0 → #3ec6e8`, 160°). Contains: current time (large, centred, SF Pro Display bold, −2.5px tracking), temperature placeholder `—°C` (smaller, SF Pro Display light, −0.5px tracking), wind and humidity placeholders in a row below that. **Settings gear** (`gearshape`) in the top-right corner of the header (no sign-in icon — accounts are cut).
- Thin 0.5px divider below the header.
- Scrollable vertical list of activity cards, one per activity the client POSTs, in **request order**. The list is the user's personalised activity list — activities can be added/removed via the ghost add-card + authoring sheet (#5b).
- Background colour: `#f2f2f7` (iOS system grouped background).
- Header weather values (temp, wind, humidity) are the forecast location's **current-hour** values from `hours[0]` (wired 2026-07-12 during #5a live-verification), rendered by `HeaderView(currentHour:)`. They fall back to `—` placeholders while loading, on error, or when the provider omitted a metric.

## Activity card (face)

Each card contains:
1. **Top row:** SF Symbol activity icon (top left, 18×18pt, 75% opacity) + activity name (SF Pro Text, 15pt medium, −0.1px tracking) + gear icon (`gearshape`, top right — opens threshold/authoring editing; #5b). **No PRO badge** — there are no `-lite`/`-pro` activity variants (grill Q3); Pro is metric-access + quantity, client-enforced, and deferred to #5b.
2. **Timeline bar:** highlights the day's best **Window**, positioned from the global `startIndex`/`endIndex` against that day's actual hour span (rendered in the response `timezone`). Green (`#34c759`) for Perfect, orange (`#ff9500`) for Good, no highlight for No Window. Window fill opacity 0.85. (The guidelines' "6am–12am" axis is illustrative — do not hardcode it; a Window can fall at any hour.)
3. **Metric chips row:** activity's `displayMetrics` (first 3). Each chip shows the metric's value at the **best-window start hour** (`startIndex`, a global index into `hours[]`). Colour tier per the scale in [`Guidelines.md`](../../../ios/guidelines/Guidelines.md); nullable metrics (`windSpeed`/`rainFall`/`cloudCover`) render `"—"` when the value is null.

The card summarises the **soonest-actionable day** for the activity (today if windowed, else the earliest non-null day by name, else "no window in the next 7 days") — read `days[]` per activity; never assume 7. See [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md).

Card background: `#ffffff`. Corner radius: 16pt. Shadow: `0 1px 3px rgba(0,0,0,0.08), 0 0 0 0.5px rgba(0,0,0,0.06)`.

## Activity set (caller-supplied — no backend list)

The engine is **activity-agnostic** ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)): the client authors activities and POSTs them; the backend holds no list and echoes them back in **request order**. Curated defaults live client-side as **Templates**.

For **#5a (core read-only)** the app seeds **two free-metric Templates** so the first launch shows real ratings with no locks (grill Q8 — land + water, core audience). Both are diurnal and use only LIVE metrics; provisional threshold numbers are pinned in the #5a build spec (unpinned finalisation is a #5b item, STATUS §4):

| `id` | Label | SF Symbol | `displayMetrics` |
|---|---|---|---|
| `cycling` | Cycling | `figure.outdoor.cycle` | `["temp", "windSpeed", "rainFall", "uV"]` |
| `fishing-lite` | Fishing Lite | `figure.fishing` | `["temp", "windSpeed", "cloudCover"]` |

Full authoring (add from Template / from scratch), the metric-picker, and Pro gating are the **#5b** wave. There is no PRO badge and no `-pro` suffix logic.

## Metric chip colour tiers

| Metric | Green | Orange | Red |
|---|---|---|---|
| `temp` (°C) | 18–32 | 33–37 | 38+ |
| `uV` | 0–3 | 4–6 | 7+ |
| `windSpeed` (km/h) | 0–20 | 21–35 | 36+ |
| `humidity` (%) | 0–60 | 61–75 | 76+ |
| `cloudCover` (%) | 0–20 | 21–60 | 61+ |

Chip style per tier (matches `ios/guidelines/Guidelines.md`):
- Green: bg `rgba(52,199,89,0.12)` / text `#1a7a35`
- Orange: bg `rgba(255,149,0,0.12)` / text `#b85c00`
- Red: bg `rgba(255,59,48,0.12)` / text `#c0392b`

## SF Symbols manifest (for the SwiftUI agent)

The app uses **SF Symbols** for all iconography (`Image(systemName:)` / `Label`). Follow these rules — hallucinated symbol names are the most common failure and render a **blank glyph**:

- **Use ONLY the exact names in the tables below.** Do **not** invent names and do **not** substitute a plausible-looking alternative.
- **If a needed glyph is not listed, use `questionmark.circle`** and leave a `// TODO: verify SF Symbol` comment — never guess a name. A visible placeholder is recoverable in review; a blank hallucinated glyph is not.
- **Availability: iOS 17+.** Symbols introduced after iOS 17 are unavailable on the deployment target and render blank. Do not use newer symbols even if the HIG skill mentions them.
- **Accessibility:** pair every symbol with a label (`Label`, or `.accessibilityLabel`) per the `apple-hig` skill's `sf-symbols.md`.
- The **project owner verifies every name below in the SF Symbols app before the build.** Rows marked **⚠︎ verify** are ones the author was less certain exist on iOS 17 — confirm those first (but confirm all).

**A. Activity template icons** (§ Activity set)

| Activity | `id` | SF Symbol | Verify |
|---|---|---|---|
| Cycling | `cycling` | `figure.outdoor.cycle` | |
| Fishing Lite | `fishing-lite` | `figure.fishing` | ⚠︎ verify |
| Running (#5b Template) | `running` | `figure.run` | ⚠︎ verify |
| Stargazing (#5b Template, nocturnal) | `stargazing` | `moon.stars.fill` | |

The card icon is explicit per activity as of #5b (`AuthoredActivity.iconSymbol`, drawn through the single `ActivityIconView` seam); the `label.contains("fishing")` heuristic survives only as a legacy fallback. New Templates extend this table — verified names only.

**B. Metric chip icons** (live metrics; **✓ used by the #5a seed Templates**, others are for #5b completeness)

| Metric | SF Symbol | In #5a seed | Verify |
|---|---|---|---|
| `temp` | `thermometer.medium` | ✓ | |
| `windSpeed` | `wind` | ✓ | |
| `rainFall` | `cloud.rain.fill` | ✓ | |
| `uV` | `sun.max.fill` | ✓ | |
| `cloudCover` | `cloud.fill` | ✓ | |
| `humidity` | `humidity.fill` | — | ⚠︎ verify |
| `visibility` | `eye.fill` | — | |
| `moon` | `moon.stars.fill` | — | |
| `dustAlert` | `sun.dust.fill` | — | ⚠︎ verify |

Coming-soon metrics (`darkness`/`douglasScale`/`swellHeight`/`swellLength`/`tide`/`seaWarning`) are **not displayable** in #5a (backend rejects them) — no icons needed until their features land.

**C. System / navigation / state**

| Purpose | SF Symbol | Verify |
|---|---|---|
| Settings — header top-right gear | `gearshape` | |
| Card authoring gear (wired in #5b — opens the editor) | `gearshape` | |
| Error state — `ContentUnavailableView` (provider/server down) | `wifi.slash` | |
| Location permission note (Settings, optional) | `location.fill` / `location.slash` | |
| Ghost add-card / from-scratch / empty state (#5b) | `plus.circle` | |
| Settings geocode search result row (#5b) | `mappin.and.ellipse` | |
| Editor metric-picker selection tick (#5b) | `checkmark` | |
| **Unlisted-glyph fallback (the guardrail above)** | `questionmark.circle` | |

Not symbols: the `NavigationLink` disclosure chevron is system-provided (do not add one manually), and the loading state is a `ProgressView` (no symbol).

## Interactions

- **Tap card body** → pushes the 7-day timeline detail (over all of the activity's `days[]`).
- **Tap header gear** → Settings sheet.
- **Tap card gear** → threshold/authoring editor (sheet; #5b).
- **Tap ghost add-card** → activity creation (from Template or scratch; #5b).

There are **no sign-in entry points** — accounts are cut (ADR-0001).

## Typography

- SF Pro Display — headings (time, temperature in header).
- SF Pro Text — all body text (activity names, metric chips, labels).
- Tight letter-spacing on headings (−2.5px on time, −0.5px on temperature). Default on body.

## Colour palette

See `ios/guidelines/Guidelines.md` for the complete token table.

## Dark mode

Deferred. Light mode only at launch.

## Platform

iOS 17+, Swift, SwiftUI, MVVM. No third-party Swift packages.

---

## Mockup vs. API contract — for the SwiftUI agent

The React/Vite prototype at `ios/src/app/` is a **visual reference only** — it will be deleted once the SwiftUI app exists. Its TypeScript types do **not** match the API contract. Use the backend response shape (Issue #4) as the source of truth, not the mockup types.

Specific mismatches the SwiftUI agent must NOT replicate:

| Mockup (visual prototype) | Real API (source of truth) | Notes |
|---|---|---|
| Single top-level `condition`/`bestTime` per activity | Per-activity **`days[]`**, each `{ dayIndex, rating, startIndex?, endIndex?, duration? }` | The result is 7-day day-bucketed, not one window. `days.length` is **per-activity** (7/8 diurnal, one shorter nocturnal) — never hardcode 7. The card renders the soonest-actionable day; the detail renders all days. See [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md). |
| `condition: 'perfect' \| 'good' \| 'none'` | `rating: "perfect" \| "good" \| null` (per day) | The no-window state is JSON `null`, not the string `"none"`. Model as an optional in Swift. |
| `bestTimeStart`, `bestTimeEnd` (clock hours) | `startIndex`, `endIndex` — **global** 0-based indices into `forecast.hours` | Indices are NOT clock hours. There is **no `hour` field** on the hourly object (dropped, ADR-0004). Derive clock times from `forecastStart` + the response **`timezone`** + `index`, rendered in the **location's** zone (not the device zone). |

The mockup timeline positions the highlight using clock-hour math because it hardcodes a 6am–midnight axis. The SwiftUI implementation must compute each day's timeline Window from the **global** `startIndex`/`endIndex` against the actual `hours` array, positioned within that day's real hour span.
