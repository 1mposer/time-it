# Implementation spec — Issue #5a: Core iOS app

> ✅ **BUILT (2026-07-06), LIVE-VERIFIED + AUDITED, merged to `main` 2026-07-12 — historical record; do not build from this.** The future-tense instructions below (TDD ordering, file scaffolding) describe work that is DONE at `ios/TimeIt/`. Known post-build drift: `HourlyWeather.label(for:)` (referenced in §Models and §Metric chips) was **deleted 2026-07-15** — the display-name table now lives in `MetricCatalog.displayName(for:)` behind the `MetricCatalogProviding` seam. **The soonest-actionable card roll-forward (this spec's `cardDay(for:)` contract, day-label rule, and related acceptance items) was CANCELLED 2026-07-20** — card = day 0 only, none-state "No window today/tonight"; see the [ADR-0004 amendment 2026-07-20](../../adr/0004-day-bucketed-rating-wire-shape.md). Current truth: [STATUS.md](../../STATUS.md) §5 + CLAUDE.md.

> Build the native iPhone app that renders the 7-day activity dashboard against the **current** backend contract: **`POST /api/v1/rating`** with a `{ lat, lon, activities[] }` body, **caller-supplied** activities, and a per-activity **`days[]`** response with a top-level **`timezone`**. The engine holds no activity list ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)), so the client authors and sends a small set of **seed Templates** and renders one card per sent activity, in request order. This is the **core read-only** slice ([STATUS.md](../../STATUS.md) §5): decode `days[]`/`timezone`, render a card (soonest-actionable day) + a 7-day timeline detail. No accounts ([ADR-0001](../../adr/0001-no-accounts-guest-first.md)), no authoring UI, no metric picker, no Pro gating — those are the **#5b** wave.

> Design decisions: [`design-decisions-issue-5.md`](design-decisions-issue-5.md) — the shared visual/UX + nav reference, **reconciled to this same contract** (no server-side activity list, `days[]`/`timezone`, no `hour`, no accounts, no tab bar, no `-pro`). Read it for colour/typography/layout; this spec is authoritative for the build shape. Both trace to [ADR-0001](../../adr/0001-no-accounts-guest-first.md) + [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md) (response) + [ADR-0005](../../adr/0005-custom-activity-request-schema.md) (request).
> Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md) — the canonical source of truth for all layout, colour, and typography.
> HIG reference: the **`apple-hig`** skill (installed at `.claude/skills/apple-hig/`) — Apple Human Interface Guidelines distilled for agents. **Consult it** for HIG-compliant layout, colour, materials, typography, navigation, and **SF Symbols usage** (rendering modes, weights, scale, `Label` pairing). See "HIG reference & constraints" below for how to use it correctly.
> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — read **Activity**, **Window**, **Rating**, **Index**, **Forecast start**, **Time-of-day window**, **Night-stitch**, **Display metrics** before starting.
> Authoritative wire shape: [`CLAUDE.md`](../../../CLAUDE.md) "API response contract".
> Depends on: the backend running locally at `localhost:3000` (`POST /api/v1/rating`).
> Required by: Issue #5b (personalization/authoring), Issue #6 (deploy + APNs).

**TDD required.** Write all tests before any implementation. Run red first, implement until green.

---

## Context

Build the native iPhone app that `POST`s a request to `/api/v1/rating` with the device location (GPS, falling back silently to Dubai `25.1627, 55.2077`) and a **client-authored list of seed Template activities**, then renders one dashboard card per returned activity in request order. Each card summarises the **soonest-actionable day** for that activity; tapping it opens a 7-day timeline detail. There are **no accounts** — the app opens directly to the dashboard with no sign-in, no gate, and no tab bar.

Because the backend is activity-agnostic and holds no list, the app must ship the activities to evaluate. #5a seeds **two free-metric Templates** (Cycling + Fishing-lite; see §2.3) client-side and POSTs them every load. Full authoring (add/edit/metric-picker/Pro) is #5b.

---

## HIG reference & constraints

The **`apple-hig`** skill (`.claude/skills/apple-hig/`) is the design-fidelity reference for this build. Use it to make the app feel native, but obey these two hard constraints — they are easy to violate silently:

1. **Target iOS 17+ — do NOT adopt post-17 APIs or components.** The skill's HIG corpus is written for the current OS generation (captured 2026-06-09, "OS 27"-era). SF Symbols and components introduced after iOS 17 are **not available** on the deployment target — `Image(systemName:)` with a too-new symbol renders blank, and a too-new modifier/view fails to compile. When the skill describes a control, verify it exists on iOS 17 before using it; when in doubt, use the iOS 17-safe form. Set the project's minimum deployment target to iOS 17.0 and honour `@available` accordingly.

2. **Do NOT bulk-load the whole HIG corpus.** It is ~156 files / ~140k tokens. Follow the skill's own tiered routing (`SKILL.md` + `routing-index.md`): load the Tier-1 foundations (colour, layout, materials, typography, **sf-symbols**), the iOS platform file, and only the Tier-3 component files your current surface needs (e.g. `lists-and-tables`, `buttons`, `materials`, `charts`). Pull niche files on demand, not preemptively.

### SF Symbols — usage vs. names

Two independent failure modes. The skill's `sf-symbols.md` covers **usage** (rendering modes, weight/scale matching, `Label` for accessibility) — follow it. It does **not** guarantee **valid names**: inventing a symbol name that doesn't exist on iOS 17 is the most common failure and renders a blank glyph. Therefore:

- **Use ONLY the exact SF Symbol names in the manifest** in [`design-decisions-issue-5.md`](design-decisions-issue-5.md) ("SF Symbols manifest"). **Do not invent names**, and do not swap in a plausible-looking alternative.
- **If a needed glyph is not in the manifest, use `questionmark.circle` and flag it** (a `// TODO: verify SF Symbol` comment) rather than guessing a name. A visible-but-wrong placeholder is recoverable; a hallucinated name that renders blank is not obvious in review.
- Pair every symbol with an accessibility label (`Label`, or `.accessibilityLabel`) per `sf-symbols.md`.

---

## Architecture

- MVVM. No third-party packages. iOS 17+, SwiftUI.
- `DashboardViewModel` (`@MainActor`, `ObservableObject`) drives the dashboard: owns the location request, builds the request body from the seed Templates, calls the API, and exposes decoded state.
- `APIClient` (Swift `actor`, shared singleton) performs the `POST` and decodes the response.
- `LocationManager` (`@MainActor`, `CLLocationManagerDelegate`) wraps `CLLocationManager`. Silent failure — `DashboardViewModel` falls back to Dubai coords when `location` is nil.
- Root is a single `NavigationStack` rooted at the dashboard. Settings is reached via a **top-right gear** (a sheet). No bottom tab bar (grill Q8).
- **No `AuthManager`, no `AppState`, no Keychain, no `SignInView`** — accounts are cut entirely (ADR-0001).

Organise source into these Xcode groups: `App/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Networking/`. Tests in `TimeItTests/` and `TimeItUITests/`.

---

## 1. Project setup

Create an Xcode project at `time-it/ios/TimeIt/`:
- Product name: `TimeIt`, bundle ID: `com.timeit.app`
- Interface: SwiftUI, Language: Swift, Storage: None, Include Tests: **checked** (unit + UI test targets)

Add Swift/Xcode patterns to the root `.gitignore` (xcuserstate, DerivedData, xcuserdata, xcscheme).

---

## 2. Data models

All response models are `Decodable`; field names must match the JSON keys the backend returns exactly. The request models are `Encodable`.

### 2.1 Response models (decode)

**`ForecastResponse`** — top-level API response. Fields:
- `forecastStart: String` — ISO 8601 UTC with a `Z` suffix (e.g. `"2026-06-10T14:00:00Z"`); decodes cleanly with a default `ISO8601DateFormatter`. It is the instant of `hours[0]`.
- `timezone: String` — the **forecast location's** IANA zone (e.g. `"Asia/Dubai"`). **All clock times and day labels render in this zone, not the device zone** (see §5, "time derivation").
- `activities: [ActivityRating]` — one entry per requested activity, in **request order**.
- `hours: [HourlyWeather]` — hourly forecast; **provider-determined length, up to 168. Never assume a fixed count** — read `hours.count`.

**`ActivityRating`** — one activity's evaluation result. Fields:
- `activityId: String`, `label: String` — echoed from the request `id`/`label`.
- `displayMetrics: [String]` — echoed from the request; ordered render superset.
- `days: [Day]` — dense, contiguous (`days[i].dayIndex == i`), **variable length per activity** (7 or 8 for diurnal; one shorter for a nocturnal activity — the night-stitch drops the tail evening). **Never hardcode 7 — read each activity's own `days.count`.**
- Computed: `id` (alias of `activityId`).
- **No `rating`/`startIndex`/`endIndex`/`duration`/`isPro`** at this level — those moved into `Day` (below), and `isPro`/`-pro` is deleted (grill Q3: no `-lite`/`-pro` activity variants).

**`Day`** — one day-bucket's best Window. Fields:
- `dayIndex: Int` — 0-based ordinal of the local calendar day (`0` = today). For a nocturnal activity it is the **evening's** ordinal (`0` = tonight).
- `rating: String?` — `"perfect"` | `"good"` | `nil`. `nil` means no qualifying Window that day.
- `startIndex: Int?`, `endIndex: Int?`, `duration: Int?` — present when `rating` is non-nil; **absent from the JSON when `rating` is nil** (decode as Swift optionals so the missing keys are tolerated). `startIndex`/`endIndex` are **global indices into `hours[]`**, not day-relative.
- Computed: `id` (use `dayIndex`), `hasWindow` (true when `rating != nil`), `ratingDisplay` ("Perfect" / "Good" / "No Window").

**`HourlyWeather`** — one hourly forecast entry. Fields:
- `index: Int` — `0..N-1`, position in `hours[]`. **There is no `hour` field** — it was dropped (ADR-0004); the client derives clock times from `forecastStart` + `timezone` + `index`.
- `temp`, `humidity`, `visibility`, `uV`, `windSpeed`, `rainFall`, `cloudCover` — **all `Double?`**. Originally only the wind/rain/cloud trio was optional, but live-verification (2026-07-12) hit `uV: null` at night (Meteosource returns `uv_index: null` after dark) and a non-optional `uV` failed the *whole* `ForecastResponse` decode. The decoder is now **null-tolerant**: a custom `init(from:)` decodes every metric with `decodeIfPresent` (missing key OR JSON `null` → nil → renders "—"), and non-metric fields default (`moon` → `[]`, flags → `false`, placeholders → `0`); only `index` is required, so a single unexpected null can never blank the dashboard. (Backend-side the adapter also defaults `uv_index ?? 0` so `uV` stays a number on the wire — nighttime UV genuinely is 0.)
- `moon: [String]`, `dustAlert: Bool`, `seaWarning: Bool`
- `darkness: Double`, `douglasScale: Double`, `swellHeight: Double`, `swellLength: Double`, `tide: Double` — coming-soon placeholders; they decode as their placeholder values (`0`) and are shown only on the timeline, never thresholded (see §2.3).
- Computed: `id` (alias of `index`).
- Two helpers: `formatted(for metric:) -> String` (per-metric display string, e.g. `"22°C"`, `"UV 3"`, `"13 km/h"`, `"8%"`; **returns `"—"` when the underlying value is nil** so a nullable chip shows a neutral em-dash, never a misleading `0`), and static `label(for metric:) -> String` (human label, e.g. `"Temperature"`).

### 2.2 Request models (encode)

**`RatingRequest`** — `Encodable`. Fields: `lat: Double`, `lon: Double`, `activities: [ActivityInput]`.

**`ActivityInput`** — `Encodable`. Fields (per [ADR-0005](../../adr/0005-custom-activity-request-schema.md)):
- `id: String` — client-stable, **unique within the request**; echoed back as `activityId`.
- `label: String` — non-empty.
- `displayMetrics: [String]` — non-empty, ordered render superset.
- `thresholds: [String: Threshold]` — the evaluated subset; **`thresholds.keys ⊆ displayMetrics`**.
- `window` — **omit** for #5a (both seed Templates are diurnal / whole-day). The optional `{ startHour, endHour }` local-hour window is a #5b authoring concern.

**`Threshold`** — encode as a numeric constraint `{ min?, max?, required }` (at least one bound; `required` mandatory) or a flag `{ type: "flag", forbidTrue: true, required }`. #5a's seed Templates use numeric thresholds only.

### 2.3 Seed Templates (client-authored)

The app ships **two** curated Templates (grill Q8: seed 2 free-metric activities so nothing shows a lock on first launch — land + water, core audience). Encode them as a constant `[ActivityInput]` and POST them on every load, in this order.

> ⚠️ **Provisional thresholds — dependency flag.** The exact threshold numbers for seed Templates are **unpinned** (STATUS §4, a #5b item). Use the provisional values below and mark them clearly in a comment as pending the #5b pin; do **not** block #5a on finalising them.

**Hard constraint (do not violate):** every metric in `displayMetrics` and `thresholds` **must be a LIVE metric** — `temp`, `humidity`, `windSpeed`, `rainFall`, `cloudCover`, `visibility`, `uV`, `moon`, `dustAlert` (source of truth: `src/weather/metricCatalog.js`). A coming-soon metric (`darkness`, `douglasScale`, `swellHeight`, `swellLength`, `tide`, `seaWarning`) is a hard **400**, and because validation is **atomic**, one bad metric rejects the **whole request** — the entire dashboard would fail to render, not just one card. The two seeds below use only live metrics.

| `id` | `label` | SF Symbol | `displayMetrics` | thresholds (provisional) |
|---|---|---|---|---|
| `cycling` | Cycling | `figure.outdoor.cycle` | `["temp", "windSpeed", "rainFall", "uV"]` | `temp {min:15,max:32,required:true}`, `windSpeed {max:25,required:false}`, `rainFall {max:0.2,required:true}`, `uV {max:8,required:false}` |
| `fishing-lite` | Fishing Lite | `figure.fishing` | `["temp", "windSpeed", "cloudCover"]` | `temp {min:12,max:36,required:true}`, `windSpeed {max:25,required:true}`, `cloudCover {max:80,required:false}` |

Both satisfy `thresholds.keys ⊆ displayMetrics`, carry unique `id`s, set `required` on every threshold, and are diurnal (no `window`).

---

## 3. Networking

**`APIConfig`** — provides the base URL (`http://localhost:3000` in DEBUG; the Railway HTTPS URL in release) and the `/api/v1/rating` path. `lat`/`lon` go in the **JSON body**, not the query string — there is no `ratingURL(lat:lon:)` query builder and **no `timezone` request field** (the location's zone is resolved server-side and returned in the response).

**`APIClient`** — a Swift `actor` with a shared singleton. One method: `fetchRatings(lat:lon:activities:) async throws -> ForecastResponse`. Builds a `POST` with `Content-Type: application/json`, encodes a `RatingRequest`, and decodes the response with `JSONDecoder`. Maps server responses to `APIError`:
- `502` → `APIError.providerUnavailable` — upstream weather provider failed. **Transient** — the user-facing message should suggest retrying.
- `500` → `APIError.serverError` — server-side defect; distinct from `502`.
- Any other non-2xx → `APIError.serverError(statusCode:)` (generic fallback).
- Decoding failure or unexpected response → `APIError.invalidResponse`.

> Note: every backend error body is the uniform envelope `{ "errors": [ { "path"?, "message" } ] }`. #5a's seed Templates are valid, so a validation `400` should not occur in normal operation; let the generic fallback cover it — do **not** build 400-specific recovery UI (that belongs to #5b's client-side stale-activity reconciliation).

---

## 4. Services

**`LocationManager`** — `@MainActor` class, `CLLocationManagerDelegate`, shared singleton. `@Published var location: CLLocation?`. `requestLocation()` calls `requestWhenInUseAuthorization()` then `requestLocation()` on the underlying manager. Silent failure — the delegate sets `location` on success, does nothing on error.

**Time derivation helper** (`Services/` or a `HourlyWeather` extension) — since `hour` is gone and everything renders in the **location's** zone, provide one place that, given `forecastStart` + `timezone` + an `index`, returns the wall-clock `Date`/label in that zone. It feeds: the timeline axis, the detail hour rows, and the "day name" used by the card's soonest-actionable fallback. Use a `Calendar`/`DateFormatter` pinned to `TimeZone(identifier: timezone)`; do **not** use the device zone.

**No `KeychainHelper`, no `AuthManager`** — accounts are cut (ADR-0001). Remove any Keychain usage.

---

## 5. ViewModel

**`DashboardViewModel`** — `@MainActor`, `ObservableObject`. Published state: `forecast: ForecastResponse?`, `isLoading: Bool`, `errorMessage: String?`.

- `loadForecast() async` — requests location, sets `isLoading`, resolves coords (device location or Dubai fallback), calls `APIClient.fetchRatings(lat:lon:activities:)` with the seed Templates, sets `forecast` or maps the error to `errorMessage`, clears `isLoading`.
- **`cardDay(for activity: ActivityRating) -> Day?`** — the **soonest-actionable** day: the first entry in `activity.days` whose `rating != nil`. Returns `days[0]` when today is windowed, else the earliest non-null day, else `nil` (→ "no window in the next 7 days"). *Soonest, not best* — do not sort by rating.
- **`windowStartHour(for day: Day) -> HourlyWeather?`** — `forecast.hours[day.startIndex]` when `startIndex` is non-nil and in range; else `nil`. (Global index — no per-day offset math.)
- **`windowHours(for day: Day) -> [HourlyWeather]`** — the slice `forecast.hours[startIndex..<endIndex]` for the day's Window; empty when indices are nil or out of range.

---

## 6. Views

### `DashboardView`

Root view inside a single `NavigationStack`. Structure: gradient header → 0.5pt divider → scrollable card list. **No tab bar.** Settings is a **top-right gear** (`gearshape`) that presents a `SettingsView` sheet.

**Header** — gradient, colours/measurements from the guidelines. Shows: current wall-clock time (large, bold), and the forecast location's **current-hour** temp / wind / humidity from `hours[0]` (`HeaderView(currentHour:)`, wired 2026-07-12 during live-verification — falls back to `—°C` / `— km/h` / `—%` while loading, on error, or when the provider omitted a metric). Top-right is the **gear** (Settings), **not** a sign-in button. The header keeps its content in the safe area (a control under the status bar is untappable) while the gradient extends behind it.

**Content area** — three states driven by `vm`:
- Loading: centred `ProgressView` labelled "Checking conditions…".
- Error: `ContentUnavailableView` with a `wifi.slash` symbol; the message distinguishes `providerUnavailable` (transient — suggest retry) from `serverError`.
- Loaded: `LazyVStack` of `ActivityCardView`, one per `forecast.activities` **in request order**, each wrapped in a `NavigationLink` to `ActivityDetailView`. Cards use `.plain` button style.

Loads via `.task { await vm.loadForecast() }`.

> Out of scope for #5a (stub or omit): the ghost "add" card at the list end and per-card authoring — both #5b.

### `ActivityCardView`

Takes `activity: ActivityRating` plus the resolved `day: Day?` (from `vm.cardDay(for:)`) and `windowStartHour: HourlyWeather?`. All visual details from the guidelines.

**Top row** — SF Symbol icon (see §2.3; `contains("fishing")` can cover fishing variants) + activity `label` + gear. **No PRO badge, no `-pro` logic.** (The gear on the card is an authoring entry point deferred to #5b — stub or omit for #5a.)

**Day label** — since the card shows the *soonest-actionable* day (not always today), label which day it is by name (e.g. "Today", "Tomorrow", or the weekday) derived via the time helper in the response `timezone`. When `day` is nil, show "No window in the next 7 days" and render the timeline empty.

**Timeline** — the highlighted Window is computed from the day's **global** `startIndex`/`endIndex` positioned against that day's actual hour span (derive the day's hour range from the time helper in the location zone). Green fill for Perfect, orange for Good, no fill for No Window. **Do not hardcode a fixed 6am–midnight axis** as the old spec did — a diurnal Window can fall at any hour and would clip; span the day's real hours (and reconcile the guideline's illustrative "6am–12am" axis to the actual day range).

**Metric chips** — `activity.displayMetrics.prefix(3)`. Each chip: icon + `windowStartHour?.formatted(for: metric)` (falls back to `HourlyWeather.label(for: metric)` when `windowStartHour` is nil). Background/text colour from the metric's tier (below). Neutral grey styling when (1) there's no window start hour, or (2) the raw value is nil for a nullable metric (`windSpeed`/`rainFall`/`cloudCover`) — in which case `formatted(for:)` returns `"—"`.

Chip tier logic lives entirely in `ActivityCardView` (do not import from outside the view). Tiers per the guidelines:

| Metric | Green | Orange | Red |
|---|---|---|---|
| `temp` (°C) | 18–32 | 33–37 | 38+ |
| `uV` | 0–3 | 4–6 | 7+ |
| `windSpeed` (km/h) | 0–20 | 21–35 | 36+ |
| `humidity` (%) | 0–60 | 61–75 | 76+ |
| `cloudCover` (%) | 0–20 | 21–60 | 61+ |

Nullable metrics (`windSpeed`, `cloudCover`, `rainFall`) → neutral grey when nil.

### `ActivityDetailView`

Takes `activity: ActivityRating` and the full `forecast` (or `hours` + `days`). This is the **7-day timeline** over **all** of `activity.days`, not a single day. For each `Day`:
- A day header: the day name (derived in the response `timezone`) + `ratingDisplay`, and — when windowed — the Window's start/end clock times and `duration`.
- The hours of that day's Window (`windowHours(for:)`), one row per hour: the hour label (derived from `forecastStart` + `timezone` + `index`) followed by one chip per `displayMetrics` entry (all metrics, not just 3). A `nil`-rating day renders as "No window".

Uses `.navigationTitle(activity.label)`.

### `SettingsView`

Minimal sheet reached from the header gear (grill Q9: ship only live controls; hide a section until its feature lands). For #5a: an app "About" section and a location/permission note are sufficient. **No subscription/Pro row** (that's #5b), **no notifications section** (that's #6c), **no account/sign-in** (cut). Keep it a thin stub — do not build settings features here.

---

## 7. Info.plist additions

- `NSLocationWhenInUseUsageDescription`: `"Time It uses your location to fetch a local weather forecast."`
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking: true` (removed later when switching to Railway HTTPS).

---

## 8. Tests

### Unit tests (`TimeItTests/`)

**`ActivityRatingTests`**
- Decodes an activity with a mix of windowed and `nil`-rating days; `days.count` is read from the payload (test a 7-day and an 8-day activity — **never assume 7**).
- `days[i].dayIndex == i` (dense, contiguous).
- A `nil`-rating `Day` decodes with `startIndex`/`endIndex`/`duration` absent (Swift optionals nil); a windowed `Day` decodes them present.
- `Day.hasWindow` / `ratingDisplay` correct for perfect / good / nil.
- **No `isPro` test** — the property is deleted.

**`DayModelTests`** — `startIndex`/`endIndex` are global indices; a Window on `dayIndex >= 1` decodes with indices > 24 (guards against any accidental per-day offset).

**`ForecastResponseTests`** — decodes top-level `timezone`; `hours[]` has no `hour` key; nullable trio (`windSpeed`/`rainFall`/`cloudCover`) decodes `null` → nil.

**`MetricColorTests`**
- Each tier boundary: temp (18/33/38), UV (4/7), wind (21/36), humidity (61/76), cloudCover (21/61).
- Nil value for a nullable metric → neutral grey (not green/orange/red).
- Extract the tier logic into a testable pure function or a card test helper — structure however tests cleanest.

**`HourlyWeatherFormattedTests`**
- `formatted(for:)` returns `"—"` (or the em-dash variant the implementation picks) when `windSpeed`/`rainFall`/`cloudCover` is nil.
- Returns the formatted value (e.g. `"13 km/h"`) when non-nil.

**`TimeDerivationTests`** — given a fixed `forecastStart` + `timezone` (e.g. `Asia/Dubai`) + `index`, the derived clock time and day label are computed in the **response** zone, independent of the host/device zone (guard against device-zone leakage — set the test host to a different zone and assert the label is unchanged).

**`SeedTemplateTests`** — the shipped seed Templates encode to valid ADR-0005 bodies: only LIVE metrics in `displayMetrics` and `thresholds`, `thresholds.keys ⊆ displayMetrics`, unique `id`s, `required` present on every threshold. (This test is the tripwire against a seed Template silently 400-ing the whole dashboard.)

**`DashboardViewModelTests`**
- `loadForecast()` sets `forecast` on success, maps `providerUnavailable`/`serverError` to `errorMessage` on failure, toggles `isLoading`.
- Falls back to Dubai coords when `LocationManager.location` is nil.
- `cardDay(for:)` returns `days[0]` when today is windowed; the earliest non-null day when today is nil; `nil` when all 7/8 days are nil (soonest, not best — a later higher-rated day does not beat an earlier lower-rated one).
- `windowStartHour(for:)` returns the correct global hour when `startIndex` is valid; `nil` when `startIndex` is nil.
- `windowHours(for:)` returns the correct `hours[startIndex..<endIndex]` slice.

> No `AuthManagerTests` — accounts are cut.

### Acceptance tests (`TimeItUITests/`)

- App launches directly to the dashboard (no sign-in, no gate, no tab bar).
- Header shows time, placeholder temp, placeholder wind/humidity, and a top-right **gear** (not a sign-in icon).
- One card per seeded Template, in request order, with correct labels/icons. **No PRO badge anywhere.**
- Each card shows a day label (Today/Tomorrow/weekday or "No window in the next 7 days"), a timeline bar, and at least one metric chip.
- Tapping a card opens the 7-day timeline detail; back returns to the dashboard.
- Server stopped → `ContentUnavailableView` error state.
- Tapping the gear opens the Settings sheet; dismissing returns to the dashboard.

---

## 9. Acceptance criteria

- [ ] Zero build errors and warnings.
- [ ] Dashboard opens directly — no sign-in, no gate, no tab bar.
- [ ] App POSTs `{ lat, lon, activities[] }` with the two seed Templates; renders one card per returned activity in request order.
- [ ] Header shows time and the current-hour temp/wind/humidity from `hours[0]` (`—` fallback while loading/error/null); top-right gear opens Settings.
- [ ] Each card shows the **soonest-actionable** day (today if windowed, else earliest non-null day by name, else "no window in the next 7 days").
- [ ] Chips show activity-specific metrics with colour tiers, values from the window start hour; nullable metrics render `"—"` when null.
- [ ] Timeline highlights the Window green (Perfect) / orange (Good) / empty (No Window), positioned from **global** `startIndex`/`endIndex` (no hardcoded 7-day or fixed-axis assumptions).
- [ ] Card tap → 7-day timeline detail over **all** `days[]` → back returns to the dashboard.
- [ ] All clock times and day labels render in the response `timezone`, not the device zone.
- [ ] Server unreachable / `502` → error view (transient framing); `500` distinguishable.
- [ ] GPS requested on load; Simulator falls back to Dubai coords silently.
- [ ] `days.count` is read per activity everywhere; nothing hardcodes 7.
