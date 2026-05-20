# Implementation spec — Issue #5: SwiftUI iOS app

> Domain glossary: [`CONTEXT.md`](../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) — must be complete and running locally before starting this issue
> Required by: [Issue #6 (Deploy)](implement-spec-issue-6-deploy-and-notifications.md)

This spec is self-contained. The implementing agent should not need any other conversation context.

---

## 1. Context

The backend now exposes a REST API (after Issue #4). This issue builds the native iPhone app that calls that API and displays the results.

**What the app does:**
- On launch, fetches `GET /api/v1/rating?lat=25.1627&lon=55.2077` from the local backend
- Shows a dashboard of activity cards (Volleyball, Boat Fishing Pro, Shore Fishing, Stargazing Lite, etc.)
- Each card shows the activity name and a rating badge (Perfect / Good / No Window)
- Tapping a card expands it to show hourly weather values for the relevant metrics during the best window
- A refresh button in the nav bar triggers a new fetch

**Platform and tools:**
- Language: Swift
- UI framework: SwiftUI
- Architecture: MVVM (`ObservableObject` + `@Published`)
- Target: iOS 17+
- Xcode: 15+
- No third-party Swift packages — use only Swift standard library and system frameworks

**During development:** the app runs in the iOS Simulator and calls the Express server on `localhost:3000`. The iOS Simulator shares the Mac's network stack, so `localhost` works without any special configuration beyond allowing local HTTP in `Info.plist`.

---

## 2. Backend API contract (what the iOS app consumes)

The full contract is in [Issue #4, Section 4](implement-spec-issue-4-http-api.md). Summary for the iOS layer:

```
GET http://localhost:3000/api/v1/rating?lat=25.1627&lon=55.2077
```

Response top level:
```json
{
  "forecastStart": "2026-05-19T15:00:00",
  "activities": [ ...ActivityRating objects... ],
  "hours": [ ...24 HourlyWeather objects... ]
}
```

`ActivityRating` object:
```json
{
  "activityId": "volleyball",
  "label": "Volleyball",
  "rating": "perfect",
  "startIndex": 3,
  "endIndex": 9,
  "duration": 6,
  "displayMetrics": ["temp", "windSpeed", "humidity", "uV"]
}
```

`HourlyWeather` object:
```json
{
  "index": 0,
  "hour": 15,
  "temp": 28.0,
  "humidity": 45.0,
  "windSpeed": 12.0,
  "rainFall": 0.0,
  "cloudCover": 10.0,
  "visibility": 10.0,
  "uV": 5.0,
  "dustAlert": false,
  "darkness": 0.0,
  "douglasScale": 0.0,
  "swellHeight": 0.0,
  "swellLength": 0.0,
  "tide": 0.0,
  "seaWarning": false
}
```

When `rating` is `null`, the `startIndex`, `endIndex`, and `duration` fields are absent from the JSON object.

---

## 3. Decisions already made (do not relitigate)

### 3.1 MVVM architecture

`DashboardViewModel` is an `@MainActor ObservableObject` that owns the network call and all published state. Views are passive — they read from the view model and call its methods; they do not own data or call the API directly.

### 3.2 `actor APIClient`

Swift actors prevent data races. `APIClient` is a singleton `actor` with `static let shared`. It holds the `JSONDecoder` as an instance property so it is not re-allocated on every call.

### 3.3 `displayMetrics` drives the detail view — no hardcoded per-activity logic

The `ActivityRating.displayMetrics` field (from the backend) tells the iOS app which metrics to show for each activity. The detail view iterates over this array generically. Adding a new activity on the backend never requires an iOS code change.

### 3.4 `hours` sliced by `startIndex..<endIndex` in the ViewModel

The ViewModel provides `func hours(for:) -> [HourlyWeather]` which slices `forecast.hours[startIndex..<endIndex]`. Views call this helper — they do not slice arrays themselves.

### 3.5 No local persistence or caching

The app fetches on launch and on manual refresh. No `URLCache` customization, no CoreData, no UserDefaults for forecast data. The backend is the source of truth.

### 3.6 `#if DEBUG` base URL switch

During development the app hits `localhost:3000`. After Issue #6 (Railway deploy), the production URL replaces the `#else` branch. This is handled in `APIConfig.swift` with a compiler directive, not a runtime flag.

### 3.7 `ContentUnavailableView` for errors

iOS 17 provides `ContentUnavailableView` for empty/error states. Use it — do not build a custom error view.

---

## 4. Project setup

### 4.1 Create the Xcode project

File > New > Project > iOS > App
- Product Name: `TimeIt`
- Team: (leave blank — no Developer account needed for Simulator)
- Bundle Identifier: `com.timeit.app`
- Interface: SwiftUI
- Language: Swift
- Storage: None
- Include Tests: unchecked

Save the project at a location **outside** the existing `time-it` Node.js repo (e.g. `~/Desktop/Projects/current/TimeIt-iOS/`). The iOS project is a separate codebase, not a subdirectory of the Node.js project.

### 4.2 Folder structure inside Xcode

Create groups (folders) in the Xcode project navigator:

```
TimeIt/
  App/
    TimeItApp.swift
    ContentView.swift
  Models/
    ForecastResponse.swift
    ActivityRating.swift
    HourlyWeather.swift
  ViewModels/
    DashboardViewModel.swift
  Views/
    DashboardView.swift
    ActivityCardView.swift
    ActivityDetailView.swift
    RatingBadgeView.swift
  Networking/
    APIConfig.swift
    APIClient.swift
```

---

## 5. All Swift files

Write every file exactly as shown. Do not add comments explaining what standard Swift constructs do.

### 5.1 `App/TimeItApp.swift`

```swift
import SwiftUI

@main
struct TimeItApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 5.2 `App/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}
```

### 5.3 `Models/ForecastResponse.swift`

```swift
import Foundation

struct ForecastResponse: Decodable {
    let forecastStart: String
    let activities: [ActivityRating]
    let hours: [HourlyWeather]
}
```

### 5.4 `Models/ActivityRating.swift`

```swift
import Foundation

struct ActivityRating: Decodable, Identifiable {
    let activityId: String
    let label: String
    let rating: String?
    let startIndex: Int?
    let endIndex: Int?
    let duration: Int?
    let displayMetrics: [String]

    var id: String { activityId }

    var hasWindow: Bool { rating != nil }

    var ratingDisplay: String {
        switch rating {
        case "perfect": return "Perfect"
        case "good":    return "Good"
        default:        return "No Window"
        }
    }
}
```

### 5.5 `Models/HourlyWeather.swift`

```swift
import Foundation

struct HourlyWeather: Decodable, Identifiable {
    let index: Int
    let hour: Int
    let temp: Double
    let humidity: Double
    let windSpeed: Double
    let rainFall: Double
    let cloudCover: Double
    let visibility: Double
    let uV: Double
    let dustAlert: Bool
    let darkness: Double
    let douglasScale: Double
    let swellHeight: Double
    let swellLength: Double
    let tide: Double
    let seaWarning: Bool

    var id: Int { index }

    func formatted(for metric: String) -> String {
        switch metric {
        case "temp":         return "\(Int(temp))°C"
        case "humidity":     return "\(Int(humidity))%"
        case "windSpeed":    return "\(Int(windSpeed)) km/h"
        case "rainFall":     return "\(rainFall) mm"
        case "cloudCover":   return "\(Int(cloudCover))%"
        case "uV":           return "UV \(Int(uV))"
        case "dustAlert":    return dustAlert ? "Dust Alert" : "Clear"
        case "douglasScale": return "Sea \(Int(douglasScale))"
        case "swellHeight":  return "\(swellHeight) m"
        case "seaWarning":   return seaWarning ? "Warning" : "Clear"
        case "darkness":     return "Bortle \(Int(darkness))"
        default:             return "—"
        }
    }

    static func label(for metric: String) -> String {
        switch metric {
        case "temp":         return "Temperature"
        case "humidity":     return "Humidity"
        case "windSpeed":    return "Wind Speed"
        case "rainFall":     return "Rainfall"
        case "cloudCover":   return "Cloud Cover"
        case "uV":           return "UV Index"
        case "dustAlert":    return "Dust"
        case "douglasScale": return "Sea State"
        case "swellHeight":  return "Swell Height"
        case "seaWarning":   return "Sea Warning"
        case "darkness":     return "Sky Darkness"
        default:             return metric
        }
    }
}
```

### 5.6 `Networking/APIConfig.swift`

```swift
import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = "http://localhost:3000"
    #else
    static let baseURL = "https://REPLACE_WITH_RAILWAY_URL"
    #endif

    static func ratingURL(lat: Double, lon: Double, timezone: String = "UTC") -> URL {
        var components = URLComponents(string: "\(baseURL)/api/v1/rating")!
        components.queryItems = [
            URLQueryItem(name: "lat",      value: String(lat)),
            URLQueryItem(name: "lon",      value: String(lon)),
            URLQueryItem(name: "timezone", value: timezone),
        ]
        return components.url!
    }
}
```

Note: Replace `REPLACE_WITH_RAILWAY_URL` with the actual URL after Issue #6 is complete.

### 5.7 `Networking/APIClient.swift`

```swift
import Foundation

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()

    func fetchAllRatings(lat: Double, lon: Double) async throws -> ForecastResponse {
        let url = APIConfig.ratingURL(lat: lat, lon: lon)
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.serverError(statusCode: http.statusCode)
        }

        return try decoder.decode(ForecastResponse.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:        return "Invalid server response."
        case .serverError(let code):  return "Server error (\(code))."
        }
    }
}
```

### 5.8 `ViewModels/DashboardViewModel.swift`

```swift
import Foundation

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var forecast: ForecastResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let lat = 25.1627
    private let lon = 55.2077

    func loadForecast() async {
        isLoading = true
        errorMessage = nil
        do {
            forecast = try await APIClient.shared.fetchAllRatings(lat: lat, lon: lon)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func hours(for activity: ActivityRating) -> [HourlyWeather] {
        guard let forecast,
              let start = activity.startIndex,
              let end = activity.endIndex else { return [] }
        return Array(forecast.hours[start..<end])
    }
}
```

### 5.9 `Views/RatingBadgeView.swift`

```swift
import SwiftUI

struct RatingBadgeView: View {
    let rating: String?

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private var label: String {
        switch rating {
        case "perfect": return "Perfect"
        case "good":    return "Good"
        default:        return "No Window"
        }
    }

    private var color: Color {
        switch rating {
        case "perfect": return .green
        case "good":    return .orange
        default:        return .gray
        }
    }
}
```

### 5.10 `Views/ActivityDetailView.swift`

```swift
import SwiftUI

struct ActivityDetailView: View {
    let activity: ActivityRating
    let hours: [HourlyWeather]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let start = activity.startIndex, let end = activity.endIndex {
                Text("Best window: hours \(start)–\(end) (\(activity.duration ?? 0)h)")
                    .font(.subheadline.weight(.medium))
            }

            ForEach(activity.displayMetrics, id: \.self) { metric in
                HStack(alignment: .top) {
                    Text(HourlyWeather.label(for: metric))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(hours) { hour in
                                Text(hour.formatted(for: metric))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### 5.11 `Views/ActivityCardView.swift`

```swift
import SwiftUI

struct ActivityCardView: View {
    let activity: ActivityRating
    let hours: [HourlyWeather]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.label)
                        .font(.headline)
                    if activity.hasWindow, let duration = activity.duration,
                       let start = activity.startIndex {
                        Text("\(duration)h window · starts in \(start)h")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                RatingBadgeView(rating: activity.rating)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.leading, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            .padding()

            if isExpanded && activity.hasWindow {
                Divider()
                ActivityDetailView(activity: activity, hours: hours)
                    .padding()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}
```

### 5.12 `Views/DashboardView.swift`

```swift
import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Checking conditions…")
                } else if let error = vm.errorMessage {
                    ContentUnavailableView(
                        "Could not load forecast",
                        systemImage: "wifi.slash",
                        description: Text(error)
                    )
                } else if let forecast = vm.forecast {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(forecast.activities) { activity in
                                ActivityCardView(
                                    activity: activity,
                                    hours: vm.hours(for: activity)
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Time It")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.loadForecast() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)
                }
            }
        }
        .task {
            await vm.loadForecast()
        }
    }
}
```

---

## 6. `Info.plist` — allow local HTTP

iOS blocks plain HTTP by default. Add this to `Info.plist` (in the Xcode project, not a standalone file) to allow calls to `localhost` during simulator development:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

To add this in Xcode: open `Info.plist` as source code (right-click > Open As > Source Code) and insert the above block inside the root `<dict>`.

**Remove this entry** after Issue #6 when the app is updated to use the Railway HTTPS URL.

---

## 7. Acceptance criteria

- [ ] App builds in Xcode with zero errors and zero warnings for the iOS Simulator target.
- [ ] With the Express server running locally (`npm run dev`), launching the app in the Simulator shows the activity dashboard — at least one activity card is visible.
- [ ] Rating badges display correctly: green "Perfect", orange "Good", gray "No Window".
- [ ] Tapping a card with a non-null rating expands it with an animation and shows the detail view with metric rows.
- [ ] Tapping an expanded card collapses it.
- [ ] Tapping a "No Window" card does nothing (no expand — `isExpanded` can toggle but `ActivityDetailView` is only shown when `activity.hasWindow` is true).
- [ ] The refresh button (↻) in the nav bar triggers a new network call; `ProgressView` is shown while loading.
- [ ] With the Express server stopped, the app shows `ContentUnavailableView` with a wifi.slash icon and an error message — it does not crash.
- [ ] The `hours` shown in the detail view correspond only to the window (startIndex to endIndex), not all 24 hours.

---

## 8. Related artifacts

- [`CONTEXT.md`](../CONTEXT.md) — domain glossary.
- [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) — defines the exact JSON contract this app decodes. Must be complete and running before this issue can be tested.
- [Issue #6 (Deploy)](implement-spec-issue-6-deploy-and-notifications.md) — after deploy, update `APIConfig.swift` `#else` branch with the Railway URL and remove `NSAllowsLocalNetworking` from `Info.plist`.
