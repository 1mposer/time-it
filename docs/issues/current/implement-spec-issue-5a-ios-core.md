# Implementation spec — Issue #5a: Core iOS app

> Design decisions: [`design-decisions-issue-5.md`](design-decisions-issue-5.md) — read before starting.
> Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md) — the canonical source of truth for all layout, colour, and typography decisions.
> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: Issue #4 HTTP API — must be running locally on `localhost:3000`.
> Required by: Issue #5b, Issue #6.

**TDD required.** Write all tests before any implementation. Run red first, implement until green.

---

## Context

Build the native iPhone app that calls the backend's `GET /api/v1/rating?lat=&lon=` endpoint and displays a dashboard of 5 activity cards. GPS provides the location; Dubai coordinates (`25.1627, 55.2077`) are the silent fallback. Sign in with Apple is available but optional — guests see the full activity list.

---

## Architecture

- MVVM. No third-party packages. iOS 17+, SwiftUI.
- `AppState` enum: `.guest` | `.authenticated(appleUserId: String)` — owned by `AuthManager`.
- `AuthManager` stores the Apple user ID in Keychain only. `syncWithBackend()` is a stub (Issue #6a scope).
- `DashboardViewModel` drives the dashboard. It owns location requests and the API call.
- `APIClient` (Swift actor) performs the network request and decodes the response.
- `LocationManager` wraps `CLLocationManager`. Falls back silently — `DashboardViewModel` uses Dubai if `location` is nil.
- Progressive auth: no launch gate. Three sign-in entry points trigger `SignInView` as a sheet (see design decisions doc).

---

## 1. Project setup

Create an Xcode project at `time-it/ios/TimeIt/`:
- Product name: `TimeIt`, bundle ID: `com.timeit.app`
- Interface: SwiftUI, Language: Swift, Storage: None, Include Tests: **checked** (creates both unit and UI test targets)

Organise source into these Xcode groups: `App/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Networking/`. Tests go in `TimeItTests/` and `TimeItUITests/`.

Add Swift/Xcode patterns to the root `.gitignore` (xcuserstate, DerivedData, xcuserdata, xcscheme).

---

## 2. Data models

All models are `Decodable`. Field names must match the JSON keys the backend returns exactly.

**`ForecastResponse`** — top-level API response. Fields: `forecastStart` (ISO 8601 string), `activities` (array of `ActivityRating`), `hours` (array of `HourlyWeather`).

**`ActivityRating`** — one activity's evaluation result. Fields: `activityId`, `label`, `rating` (optional string: `"perfect"` | `"good"` | nil), `startIndex` (optional Int), `endIndex` (optional Int), `duration` (optional Int), `displayMetrics` (string array). Computed properties: `id` (alias of `activityId`), `hasWindow` (true when rating is non-nil), `ratingDisplay` ("Perfect" / "Good" / "No Window"), `isPro` (true when `activityId` ends in `-pro`).

**`HourlyWeather`** — one hourly forecast entry. Fields: `index`, `hour`, `temp`, `humidity`, `windSpeed`, `rainFall`, `cloudCover`, `visibility`, `uV`, `dustAlert` (Bool), `darkness`, `douglasScale`, `swellHeight`, `swellLength`, `tide`, `seaWarning` (Bool). Computed: `id` (alias of `index`). Two methods: `formatted(for metric:) -> String` (returns display string per metric, e.g. `"22°C"`, `"UV 3"`, `"13 km/h"`, `"8%"`), and static `label(for metric:) -> String` (returns human label, e.g. `"Temperature"`).

---

## 3. Networking

**`APIConfig`** — provides the base URL (`http://localhost:3000` in DEBUG, Railway HTTPS URL in release) and a `ratingURL(lat:lon:timezone:)` builder that constructs the full URL with query items.

**`APIClient`** — a Swift `actor` with a shared singleton. One method: `fetchAllRatings(lat:lon:) async throws -> ForecastResponse`. Decodes with `JSONDecoder`. Throws `APIError.invalidResponse` or `APIError.serverError(statusCode:)` on failure.

---

## 4. Services

**`KeychainHelper`** — static helpers: `save(key:value:)`, `read(key:) -> String?`, `delete(key:)`. Uses `kSecClassGenericPassword`.

**`LocationManager`** — `@MainActor` class, `CLLocationManagerDelegate`. Shared singleton. `@Published var location: CLLocation?`. `requestLocation()` calls `requestWhenInUseAuthorization()` then `requestLocation()` on the underlying manager. Silent failure — delegate sets `location` on success, does nothing on error.

**`AuthManager`** — `@MainActor` class, shared singleton, `ObservableObject`. `@Published var appState: AppState`. On `init`, reads Keychain for `"appleUserId"` and sets state accordingly. `handleSignIn(result:)` extracts the Apple user ID from the credential, saves to Keychain, updates `appState`. `signOut()` deletes from Keychain, resets to `.guest`.

---

## 5. ViewModel

**`DashboardViewModel`** — `@MainActor`, `ObservableObject`. Published state: `forecast: ForecastResponse?`, `isLoading: Bool`, `errorMessage: String?`.

- `loadForecast() async` — requests location, sets `isLoading`, calls `APIClient`, sets `forecast` or `errorMessage`, clears `isLoading`.
- `windowStartHour(for activity: ActivityRating) -> HourlyWeather?` — returns `forecast.hours[activity.startIndex]` when both exist and the index is in range; otherwise `nil`.
- `hours(for activity: ActivityRating) -> [HourlyWeather]` — returns the slice `forecast.hours[startIndex..<endIndex]` for the activity's window; empty array if indices are nil.

---

## 6. Views

### `DashboardView`

Root view. Uses `NavigationStack`. Structure: gradient header → 0.5pt divider → scrollable card list → tab bar (via `.safeAreaInset`).

**Header** — gradient, colours and measurements from the guidelines doc. Shows: current wall-clock time (large, bold), `—°C` placeholder, `— km/h` and `—%` placeholders, sign-in circle button top-right. The header ignores the top safe area so the gradient extends behind the status bar.

**Content area** — three states driven by `vm`:
- Loading: centered `ProgressView` with label "Checking conditions…"
- Error: `ContentUnavailableView` with `wifi.slash` symbol
- Loaded: `LazyVStack` of `ActivityCardView` items wrapped in `NavigationLink`s to `ActivityDetailView`. Cards use `.plain` button style.

**Tab bar** — three icon-only buttons at the bottom (Activities active/orange, + inactive, Profile inactive). + button triggers sign-in sheet if guest. All buttons have 44×44pt minimum touch target.

Loads forecast via `.task { await vm.loadForecast() }`. Presents `SignInView` as a `.sheet`.

### `ActivityCardView`

Takes `activity: ActivityRating` and `windowStartHour: HourlyWeather?`. All visual details from the guidelines doc.

**Top row** — icon (SF Symbol, see activity table in design decisions doc, `contains("fishing")` covers all three fishing IDs), name, optional PRO badge (when `activity.isPro`), gear button.

**Timeline** — `GeometryReader` computes the window's left offset and width as fractions of the bar's total width (18-hour span, 6am–midnight). Green fill for Perfect, orange for Good, no fill for No Window. Time-axis labels (6am, 12pm, 6pm, 12am) below.

**Metric chips** — `activity.displayMetrics.prefix(3)`. Each chip: icon + formatted value from `windowStartHour?.formatted(for: metric)` (falls back to `HourlyWeather.label(for: metric)` when `windowStartHour` is nil). Background and text colour determined by the metric's tier against the thresholds in the design decisions doc. When `windowStartHour` is nil, chips render with neutral grey styling.

Chip tier logic (all in `ActivityCardView` — do not import this logic from outside the view):

| Metric | Raw value source on `HourlyWeather` |
|---|---|
| `temp` | `.temp` |
| `uV` | `.uV` |
| `windSpeed` | `.windSpeed` |
| `humidity` | `.humidity` |
| `cloudCover` | `.cloudCover` |

### `ActivityDetailView`

Takes `activity: ActivityRating` and `hours: [HourlyWeather]` (the window slice). Shows a header line with start hour, end hour, and duration. Below it, one row per hour: the hour label followed by one chip per `displayMetrics` entry (all metrics, not just 3). Uses `.navigationTitle(activity.label)`.

### `SignInView`

Sheet. App name, subtitle, `SignInWithAppleButton` (scopes: none), "Continue as guest" button that dismisses. On successful sign-in calls `authManager.handleSignIn(result:)` then dismisses.

---

## 7. Info.plist additions

- `NSLocationWhenInUseUsageDescription`: `"Time It uses your location to fetch a local weather forecast."`
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking: true` (removed in Issue #6b when switching to Railway HTTPS)

---

## 8. Tests

### Unit tests (`TimeItTests/`)

**`ActivityRatingTests`**
- `hasWindow` is true when rating is non-nil, false when nil
- `ratingDisplay` returns the correct string for each of the three cases
- `isPro` is true for an ID ending in `-pro`, false otherwise

**`MetricColorTests`**
- Verify each tier boundary for: temp (18/33/38), UV (4/7), wind (21/36), humidity (61/76), cloudCover (21/61)
- The test instantiates an `ActivityCardView` test helper or extracts the tier logic into a testable pure function — structure however makes testing cleanest

**`DashboardViewModelTests`**
- `loadForecast()` sets `forecast` on success, `errorMessage` on failure, toggles `isLoading` correctly
- Falls back to Dubai coords when `LocationManager.location` is nil
- `windowStartHour(for:)` returns the correct hour when forecast is loaded and `startIndex` is valid
- `windowStartHour(for:)` returns nil when `startIndex` is nil

**`AuthManagerTests`**
- `appState` is `.guest` on init when Keychain is empty
- `appState` is `.authenticated` on init when Keychain has a saved user ID
- `signOut()` clears Keychain and resets to `.guest`

### Acceptance tests (`TimeItUITests/`)

- App launches to the dashboard (no sign-in gate)
- Header shows time, placeholder temp, placeholder wind/humidity, sign-in button
- 5 cards visible with correct labels in backend order
- Boat Fishing Pro card shows "PRO" badge
- Each card has a timeline bar and at least one metric chip
- Tapping a card opens the detail screen; back button returns to dashboard
- Server stopped → error view shown
- Sign-in button → sheet appears; "Continue as guest" → sheet dismissed

---

## 9. Acceptance criteria

- [ ] Zero build errors and warnings
- [ ] Dashboard opens directly — no sign-in gate
- [ ] Header shows time and `—` placeholders for weather
- [ ] 5 cards in backend order with correct names, icons, PRO badge on `boat-fishing-pro`
- [ ] Chips show activity-specific metrics with colour tiers, values from window start hour
- [ ] Timeline window green (Perfect) / orange (Good) / empty (No Window)
- [ ] Card tap → detail screen → back returns to dashboard
- [ ] Server unreachable → `ContentUnavailableView` with `wifi.slash`
- [ ] Sign-in sheet opens from header icon and + tab; guest dismissal leaves dashboard unchanged
- [ ] Successful Sign in with Apple → `appState` becomes `.authenticated`
- [ ] GPS requested on load; Simulator uses Dubai coords silently
