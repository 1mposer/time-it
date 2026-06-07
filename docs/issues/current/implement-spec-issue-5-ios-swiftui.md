# Implementation spec — Issue #5: SwiftUI iOS app

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — must be complete and running locally before starting this issue
> Required by: [Issue #6](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6))

**This issue is split into two sequential sub-issues.** Implement #5a first, compact, then implement #5b. Each sub-issue is fully self-contained — the implementing agent needs no other conversation context.

---

## Sub-issue #5a — Core iOS app

### Context

The backend exposes `GET /api/v1/rating?lat=&lon=` (Issue #4). This sub-issue builds the native iPhone app that calls it and displays results. The app uses GPS for location. Sign in with Apple is available but not required — guests see the full dashboard and sign in only when they want to personalise.

**Architecture decisions (do not relitigate):**
- Progressive auth: app opens directly to the dashboard. Sign in with Apple is triggered by a CTA on the dashboard, not a launch gate.
- AppState: `.guest` | `.authenticated(appleUserId: String)`. Stored in `AuthManager`.
- Location: request "When In Use" GPS on dashboard load. Fall back to Dubai coordinates (`25.1627, 55.2077`) if location is unavailable.
- Guest sees all 5 activities. Personalisation (filtering by selected activities) comes in #5b.
- After sign-in in #5a: app transitions to `.authenticated` state — same dashboard, no filtering yet. Filtering and onboarding are #5b's scope.
- No backend call for auth in this sub-issue. `AuthManager` stores the Apple user ID in Keychain only. The `syncWithBackend()` method is a documented stub for Issue #6a.
- Client-side StoreKit gating (Issue #5b). The backend always returns all activities.
- Platform: iOS 17+, Swift, SwiftUI, MVVM. No third-party Swift packages.

---

### 1. Project setup

**Create the Xcode project:**
- File > New > Project > iOS > App
- Product Name: `TimeIt`
- Bundle Identifier: `com.timeit.app`
- Interface: SwiftUI, Language: Swift, Storage: None, Include Tests: unchecked
- Save at `~/Desktop/Projects/TimeIt-iOS/` (outside the Node.js repo)

**Folder structure inside Xcode:**

```
TimeIt/
  App/
    TimeItApp.swift
    AppState.swift
  Models/
    ForecastResponse.swift
    ActivityRating.swift
    HourlyWeather.swift
  Services/
    KeychainHelper.swift
    LocationManager.swift
    AuthManager.swift
  ViewModels/
    DashboardViewModel.swift
  Views/
    DashboardView.swift
    ActivityCardView.swift
    ActivityDetailView.swift
    RatingBadgeView.swift
    SignInPromptView.swift
    SignInView.swift
  Networking/
    APIConfig.swift
    APIClient.swift
```

---

### 2. All Swift files

#### `App/AppState.swift`

```swift
import Foundation

enum AppState: Equatable {
    case guest
    case authenticated(appleUserId: String)
}
```

#### `App/TimeItApp.swift`

```swift
import SwiftUI

@main
struct TimeItApp: App {
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(authManager)
        }
    }
}
```

#### `Models/ForecastResponse.swift`

```swift
import Foundation

struct ForecastResponse: Decodable {
    let forecastStart: String
    let activities: [ActivityRating]
    let hours: [HourlyWeather]
}
```

#### `Models/ActivityRating.swift`

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
    var isPro: Bool { activityId == "boat-fishing-pro" }

    var ratingDisplay: String {
        switch rating {
        case "perfect": return "Perfect"
        case "good":    return "Good"
        default:        return "No Window"
        }
    }
}
```

#### `Models/HourlyWeather.swift`

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

#### `Services/KeychainHelper.swift`

```swift
import Foundation
import Security

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

#### `Services/LocationManager.swift`

```swift
import CoreLocation
import Foundation

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var location: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.location = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Failure is silent — DashboardViewModel falls back to Dubai coords
    }
}
```

#### `Services/AuthManager.swift`

```swift
import AuthenticationServices
import Foundation

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var appState: AppState = .guest

    override init() {
        super.init()
        if let userId = KeychainHelper.read(key: "appleUserId") {
            appState = .authenticated(appleUserId: userId)
        }
    }

    func handleSignIn(result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        let userId = credential.user
        KeychainHelper.save(key: "appleUserId", value: userId)
        appState = .authenticated(appleUserId: userId)
        // TODO: Issue #6a — call syncWithBackend(appleUserId:identityToken:) here
    }

    func signOut() {
        KeychainHelper.delete(key: "appleUserId")
        appState = .guest
    }

    // TODO: Issue #6a — implement this method
    // func syncWithBackend(appleUserId: String, identityToken: String) async throws { }
}
```

#### `Networking/APIConfig.swift`

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

#### `Networking/APIClient.swift`

```swift
import Foundation

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()

    func fetchAllRatings(lat: Double, lon: Double) async throws -> ForecastResponse {
        let url = APIConfig.ratingURL(lat: lat, lon: lon)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.serverError(statusCode: http.statusCode) }
        return try decoder.decode(ForecastResponse.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:       return "Invalid server response."
        case .serverError(let code): return "Server error (\(code))."
        }
    }
}
```

#### `ViewModels/DashboardViewModel.swift`

```swift
import Foundation

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var forecast: ForecastResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let locationManager = LocationManager.shared
    private let dubaiLat = 25.1627
    private let dubaiLon = 55.2077

    func loadForecast() async {
        locationManager.requestLocation()
        isLoading = true
        errorMessage = nil
        let lat = locationManager.location?.coordinate.latitude  ?? dubaiLat
        let lon = locationManager.location?.coordinate.longitude ?? dubaiLon
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
              let end   = activity.endIndex else { return [] }
        return Array(forecast.hours[start..<end])
    }
}
```

#### `Views/SignInPromptView.swift`

```swift
import SwiftUI

struct SignInPromptView: View {
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack {
                Image(systemName: "person.crop.circle")
                Text("Sign in to personalise your activities")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
```

#### `Views/SignInView.swift`

```swift
import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Time It")
                .font(.largeTitle.bold())
            Text("Sign in to personalise your activity feed and receive push alerts.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            SignInWithAppleButton(.continue, onRequest: { request in
                request.requestedScopes = []
            }, onCompletion: { result in
                authManager.handleSignIn(result: result)
                dismiss()
            })
            .frame(height: 50)
            .padding(.horizontal)
            Button("Continue as guest") { dismiss() }
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
```

#### `Views/RatingBadgeView.swift`

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

#### `Views/ActivityDetailView.swift`

```swift
import SwiftUI

struct ActivityDetailView: View {
    let activity: ActivityRating
    let hours: [HourlyWeather]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let start = activity.startIndex, let end = activity.endIndex {
                Text("Best window: hours \(start)–\(end - 1) (\(activity.duration ?? 0)h)")
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

#### `Views/ActivityCardView.swift`

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
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
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

#### `Views/DashboardView.swift`

```swift
import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSignIn = false

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
                            if authManager.appState == .guest {
                                SignInPromptView { showSignIn = true }
                            }
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
        .task { await vm.loadForecast() }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }
}
```

---

### 3. `Info.plist`

Add to `Info.plist` (open as source in Xcode):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Time It uses your location to fetch a local weather forecast.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

Remove `NSAllowsLocalNetworking` in Issue #6b when switching to the Railway HTTPS URL.

---

### 4. Acceptance criteria

- [ ] App builds in Xcode with zero errors and zero warnings.
- [ ] With `npm run dev` running, the Simulator shows all 5 activity cards.
- [ ] Rating badges display correctly: green "Perfect", orange "Good", gray "No Window".
- [ ] Tapping a card with a non-null rating expands it and shows metric rows for the window hours only.
- [ ] Tapping again collapses the card.
- [ ] With the server stopped, `ContentUnavailableView` with a wifi.slash icon is shown — no crash.
- [ ] Refresh button (↻) triggers a new network call.
- [ ] A "Sign in to personalise" banner is visible above the cards when `appState == .guest`.
- [ ] Tapping the banner shows `SignInView` as a sheet.
- [ ] "Continue as guest" dismisses the sheet; the dashboard remains unchanged.
- [ ] After successful Sign in with Apple, `appState` becomes `.authenticated` and the banner disappears.
- [ ] GPS is requested on dashboard load. On Simulator (no GPS), Dubai coords are used silently.

---

## Sub-issue #5b — Personalization layer

**Depends on:** #5a complete (the Xcode project at `~/Desktop/Projects/TimeIt-iOS/` must already exist)

### Context

The app (from #5a) shows all 5 activities to all users. This sub-issue adds:
- Onboarding flow triggered after first sign-in (activity selection + home location)
- Activity filtering: only selected activities shown on the dashboard
- Home location: stored in `UserDefaults`, used as the fetch coordinate
- StoreKit 2 client-side gating for the Pro activity (`boat-fishing-pro`)
- Settings screen

**Architecture decisions (do not relitigate):**
- `AppState` gets a third case: `.onboarding(appleUserId: String)`. `AuthManager` transitions there instead of `.authenticated` when `!hasCompletedOnboarding`.
- `PreferencesManager` owns `selectedActivityIds`, `homeLocation`, and `isPro` via `UserDefaults`.
- `isPro` is resolved by querying StoreKit 2 `Transaction.currentEntitlements` — not from any backend response.
- StoreKit product ID: `com.timeit.app.pro_monthly`
- Backend always returns all 5 activities; filtering is client-side only.
- `syncToBackend()` on `PreferencesManager` is a documented stub for Issue #6a.

---

### 1. New files

#### Updated `App/AppState.swift`

Replace the existing file:

```swift
import Foundation

enum AppState: Equatable {
    case guest
    case onboarding(appleUserId: String)
    case authenticated(appleUserId: String)
}
```

#### `Services/PreferencesManager.swift`

```swift
import Foundation
import StoreKit

@MainActor
class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var selectedActivityIds: Set<String> = []
    @Published var homeLocation: SavedLocation?
    @Published var isPro: Bool = false

    struct SavedLocation: Codable {
        let lat: Double
        let lon: Double
    }

    var hasCompletedOnboarding: Bool { !selectedActivityIds.isEmpty }

    init() {
        if let raw = UserDefaults.standard.stringArray(forKey: "selectedActivityIds") {
            selectedActivityIds = Set(raw)
        }
        if let data = UserDefaults.standard.data(forKey: "homeLocation"),
           let loc = try? JSONDecoder().decode(SavedLocation.self, from: data) {
            homeLocation = loc
        }
    }

    func save() {
        UserDefaults.standard.set(Array(selectedActivityIds), forKey: "selectedActivityIds")
        if let loc = homeLocation,
           let data = try? JSONEncoder().encode(loc) {
            UserDefaults.standard.set(data, forKey: "homeLocation")
        }
    }

    func checkProEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == "com.timeit.app.pro_monthly" {
                isPro = true
                return
            }
        }
        isPro = false
    }

    // TODO: Issue #6a — implement this method
    func syncToBackend() async throws { }
}
```

#### `Views/OnboardingView.swift`

```swift
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var prefs: PreferencesManager
    @State private var step: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    ActivitySelectionView(onContinue: { step = 1 })
                } else {
                    LocationPickerView(onFinish: {
                        guard case .onboarding(let userId) = authManager.appState else { return }
                        authManager.completeOnboarding(appleUserId: userId)
                    })
                }
            }
            .navigationTitle(step == 0 ? "Your Activities" : "Home Location")
        }
    }
}
```

#### `Views/ActivitySelectionView.swift`

```swift
import SwiftUI

struct ActivitySelectionView: View {
    @EnvironmentObject private var prefs: PreferencesManager
    let allActivities: [(id: String, label: String, isPro: Bool)] = [
        ("volleyball",        "Volleyball",        false),
        ("boat-fishing-pro",  "Boat Fishing (Pro)", true),
        ("boat-fishing-lite", "Boat Fishing",       false),
        ("shore-fishing",     "Shore Fishing",      false),
        ("stargazing-lite",   "Stargazing",         false),
    ]
    let onContinue: () -> Void

    var body: some View {
        List(allActivities, id: \.id) { activity in
            HStack {
                VStack(alignment: .leading) {
                    Text(activity.label)
                    if activity.isPro {
                        Text("Pro").font(.caption).foregroundColor(.orange)
                    }
                }
                Spacer()
                if prefs.selectedActivityIds.contains(activity.id) {
                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if prefs.selectedActivityIds.contains(activity.id) {
                    prefs.selectedActivityIds.remove(activity.id)
                } else {
                    prefs.selectedActivityIds.insert(activity.id)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Continue") { prefs.save(); onContinue() }
                    .disabled(prefs.selectedActivityIds.isEmpty)
            }
        }
    }
}
```

#### `Views/LocationPickerView.swift`

```swift
import CoreLocation
import SwiftUI

struct LocationPickerView: View {
    @EnvironmentObject private var prefs: PreferencesManager
    @StateObject private var locationManager = LocationManager.shared
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Set a home location so Time It always shows local conditions, even without GPS.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Use current GPS as home location") {
                locationManager.requestLocation()
                if let loc = locationManager.location {
                    prefs.homeLocation = .init(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                    prefs.save()
                }
                onFinish()
            }
            .buttonStyle(.borderedProminent)

            Button("Skip for now") { onFinish() }
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
```

#### `Views/SettingsView.swift`

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var prefs: PreferencesManager
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Activities") {
                    NavigationLink("Select activities") { ActivitySelectionView(onContinue: {}) }
                }
                Section("Location") {
                    NavigationLink("Set home location") { LocationPickerView(onFinish: {}) }
                    if let home = prefs.homeLocation {
                        Text("Home: \(home.lat, specifier: "%.4f"), \(home.lon, specifier: "%.4f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Subscription") {
                    if prefs.isPro {
                        Label("Pro — active", systemImage: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Upgrade to Pro") { showPaywall = true }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { authManager.signOut() }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showPaywall) { ProPaywallView() }
        .task { await prefs.checkProEntitlement() }
    }
}
```

#### `Views/ProPaywallView.swift`

```swift
import StoreKit
import SwiftUI

struct ProPaywallView: View {
    @EnvironmentObject private var prefs: PreferencesManager
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sailboat.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Time It Pro")
                .font(.largeTitle.bold())
            Text("Unlock Boat Fishing Pro — optimised thresholds for open-water fishing in UAE conditions.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if let product {
                Button(isPurchasing ? "Processing…" : "Subscribe \(product.displayPrice)/month") {
                    Task { await purchase(product) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
            } else {
                ProgressView()
            }

            if let error = errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            }

            Button("Restore purchases") {
                Task {
                    try? await AppStore.sync()
                    await prefs.checkProEntitlement()
                    if prefs.isPro { dismiss() }
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .task { await loadProduct() }
    }

    private func loadProduct() async {
        product = try? await Product.products(for: ["com.timeit.app.pro_monthly"]).first
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success = result {
                await prefs.checkProEntitlement()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

---

### 2. Modified files

#### `App/TimeItApp.swift` — inject `PreferencesManager`

Replace with:

```swift
import SwiftUI

@main
struct TimeItApp: App {
    @StateObject private var authManager   = AuthManager.shared
    @StateObject private var prefs         = PreferencesManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(prefs)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        switch authManager.appState {
        case .guest, .authenticated:
            DashboardView()
        case .onboarding:
            OnboardingView()
        }
    }
}
```

#### `Services/AuthManager.swift` — add `.onboarding` transition and `completeOnboarding`

Replace the `handleSignIn` and `signOut` methods:

```swift
func handleSignIn(result: Result<ASAuthorization, Error>) {
    guard case .success(let auth) = result,
          let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
    let userId = credential.user
    KeychainHelper.save(key: "appleUserId", value: userId)
    if PreferencesManager.shared.hasCompletedOnboarding {
        appState = .authenticated(appleUserId: userId)
    } else {
        appState = .onboarding(appleUserId: userId)
    }
    // TODO: Issue #6a — call syncWithBackend here
}

func completeOnboarding(appleUserId: String) {
    appState = .authenticated(appleUserId: appleUserId)
    Task { try? await PreferencesManager.shared.syncToBackend() }
}

func signOut() {
    KeychainHelper.delete(key: "appleUserId")
    appState = .guest
}
```

Also update `init()` to restore `.onboarding` if needed:

```swift
override init() {
    super.init()
    if let userId = KeychainHelper.read(key: "appleUserId") {
        if PreferencesManager.shared.hasCompletedOnboarding {
            appState = .authenticated(appleUserId: userId)
        } else {
            appState = .onboarding(appleUserId: userId)
        }
    }
}
```

#### `ViewModels/DashboardViewModel.swift` — prefer home location, filter by selected activities

Replace:

```swift
@MainActor
class DashboardViewModel: ObservableObject {
    @Published var forecast: ForecastResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let locationManager = LocationManager.shared
    private let prefs           = PreferencesManager.shared
    private let dubaiLat        = 25.1627
    private let dubaiLon        = 55.2077

    var visibleActivities: [ActivityRating] {
        guard let forecast else { return [] }
        if prefs.selectedActivityIds.isEmpty { return forecast.activities }
        return forecast.activities.filter { prefs.selectedActivityIds.contains($0.activityId) }
    }

    func loadForecast() async {
        isLoading = true
        errorMessage = nil
        let lat: Double
        let lon: Double
        if let home = prefs.homeLocation {
            lat = home.lat
            lon = home.lon
        } else {
            locationManager.requestLocation()
            lat = locationManager.location?.coordinate.latitude  ?? dubaiLat
            lon = locationManager.location?.coordinate.longitude ?? dubaiLon
        }
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
              let end   = activity.endIndex else { return [] }
        return Array(forecast.hours[start..<end])
    }
}
```

#### `Views/DashboardView.swift` — use `visibleActivities`, add settings nav, Pro lock overlay

Replace the `ForEach(forecast.activities)` loop with `ForEach(vm.visibleActivities)`.

Add a settings gear to the toolbar:

```swift
ToolbarItem(placement: .navigationBarLeading) {
    NavigationLink { SettingsView() } label: {
        Image(systemName: "gearshape")
    }
}
```

#### `Views/ActivityCardView.swift` — Pro lock overlay

Add `@EnvironmentObject private var prefs: PreferencesManager` and a lock overlay when the activity is Pro and `!prefs.isPro`:

```swift
.overlay {
    if activity.isPro && !prefs.isPro {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.title2)
                    Text("Pro").font(.caption.weight(.semibold))
                }
            }
            .onTapGesture { showPaywall = true }
    }
}
.sheet(isPresented: $showPaywall) { ProPaywallView() }
```

Add `@State private var showPaywall = false` to `ActivityCardView`.

---

### 3. Acceptance criteria

- [ ] App builds with zero errors.
- [ ] After sign-in, app shows `OnboardingView` (activity selection, then location picker) for a new user.
- [ ] After completing onboarding, app transitions to `DashboardView` showing only selected activities.
- [ ] Re-launching the app with an existing Keychain entry skips onboarding and goes straight to `.authenticated` state.
- [ ] Dashboard uses home location (if set) in preference to GPS.
- [ ] Settings screen accessible via gear icon. Activity selection and location picker navigable from Settings.
- [ ] `boat-fishing-pro` card shows a lock overlay for non-Pro users; tapping opens `ProPaywallView`.
- [ ] `ProPaywallView` fetches the StoreKit product and shows a purchase button.
- [ ] After successful purchase, `isPro` is `true` and the lock overlay is gone.
- [ ] Sign out resets `appState` to `.guest` — dashboard shows all 5 activities again with the sign-in banner.

---

## Related artifacts

- [`CONTEXT.md`](../../CONTEXT.md) — domain glossary.
- [Issue #6](current/implement-spec-issue-6-deploy-and-notifications.md) ([GitHub](https://github.com/1mposer/time-it/issues/6)) — backend auth, Railway deploy, push notifications.
