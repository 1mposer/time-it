import CoreLocation
import SwiftUI

@main
struct TimeItApp: App {

    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        // UI tests start from the first-launch seed state: wipe persisted
        // authoring + preferences BEFORE any store singleton loads them.
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET") {
            UserDefaults.standard.removeObject(forKey: ActivityStore.storageKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.homeLocationKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.lastResolvedLocationKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.dismissedTemplatesKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.showPhrasesKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.pushCalloutDismissedKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.enabledKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastSentTokenKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastUpsertAtKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.pendingDeleteKey)
        }
        // Spec 14 §1 made the REAL first launch dormant (no request, no rated
        // cards), so card/flow tests pre-persist a LIVE store instead: the two
        // templates with their prefill ranges confirmed. Harness-only — the
        // product never seeds live.
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_LIVE"),
           let data = try? JSONEncoder().encode([SeedTemplates.cycling, SeedTemplates.fishingLite]) {
            UserDefaults.standard.set(data, forKey: ActivityStore.storageKey)
        }
        // The nocturnal acceptance path (§8 parity): stargazing LIVE with its
        // wrapped 10pm–4am range — 6 night buckets, "Tonight" copy.
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_NOCTURNAL"),
           let data = try? JSONEncoder().encode([SeedTemplates.stargazing]) {
            UserDefaults.standard.set(data, forKey: ActivityStore.storageKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: Self.makeViewModel(),
                          registration: Self.makeRegistration())
        }
    }

    @MainActor
    private static func makeViewModel() -> DashboardViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            let mode: MockRatingService.Mode =
                ProcessInfo.processInfo.arguments.contains("UITEST_MOCK_FAILURE") ? .failure : .success
            return DashboardViewModel(api: MockRatingService(mode: mode),
                                      locationProvider: uiTestLocationProvider())
        }
        #endif
        return DashboardViewModel()
    }

    /// Mock runs get a fully-seamed registration (no real Keychain, APNs, or
    /// network) so the opt-in flow is deterministic; production uses .shared —
    /// the same instance the AppDelegate feeds tokens into.
    @MainActor
    private static func makeRegistration() -> DeviceRegistration {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return DeviceRegistration(
                api: UITestDevicesAPI(),
                keychain: UITestKeychain(),
                locationProvider: uiTestLocationProvider(),
                authorizer: UITestPushAuthorizer(
                    grants: !ProcessInfo.processInfo.arguments.contains("UITEST_PUSH_DENY")),
                registerForRemoteNotifications: {})
        }
        #endif
        return DeviceRegistration.shared
    }

    #if DEBUG
    /// UITEST_LOCATION feeds the mock provider a fixed fix so the card/header
    /// tests stay fed; UITEST_LOCATION_DENIED forces the denied status
    /// (acceptance §3.1's "fresh install, location denied"); with neither the
    /// provider never resolves — the not-yet-asked no-location path (#5c).
    @MainActor
    private static func uiTestLocationProvider() -> StaticLocationProvider {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_LOCATION") {
            return StaticLocationProvider(location: CLLocation(latitude: 25.2048, longitude: 55.2708))
        }
        if arguments.contains("UITEST_LOCATION_DENIED") {
            return StaticLocationProvider(authorization: .denied)
        }
        return StaticLocationProvider()
    }
    #endif
}
