import CoreLocation
import SwiftUI

@main
struct TimeItApp: App {

    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    /// UI-test launch arguments are honoured here, BEFORE any store singleton
    /// loads persisted state: UITEST_RESET wipes it, the SEED arguments
    /// pre-persist a live store (the harness's shortcut past onboarding).
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET") {
            UserDefaults.standard.removeObject(forKey: ActivityStore.storageKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.homeLocationKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.lastResolvedLocationKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.dismissedTemplatesKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.showPhrasesKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.pushCalloutDismissedKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.timezoneWarnedHomeKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.enabledKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastSentTokenKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastUpsertAtKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.pendingDeleteKey)
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_LIVE"),
           let data = try? JSONEncoder().encode([SeedTemplates.cycling, SeedTemplates.fishingLite]) {
            UserDefaults.standard.set(data, forKey: ActivityStore.storageKey)
        }
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
            // Device zone pinned to the fixture's zone so mock runs stay
            // hermetic: no timezone-mismatch alert, sim-zone-independent clock.
            return DashboardViewModel(api: MockRatingService(mode: mode),
                                      locationProvider: uiTestLocationProvider(),
                                      deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!)
        }
        #endif
        return DashboardViewModel()
    }

    /// Mock runs get a fully-seamed registration; production uses .shared —
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
    /// UITEST_LOCATION = a fixed fix; UITEST_LOCATION_DENIED = denied status;
    /// neither = the provider never resolves (the no-location path).
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
