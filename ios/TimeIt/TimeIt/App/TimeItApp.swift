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
            // dismissedTemplates: legacy showcase-ledger key, cleared by raw
            // string — the property died with the template removal.
            UserDefaults.standard.removeObject(forKey: "dismissedTemplates")
            UserDefaults.standard.removeObject(forKey: PreferencesStore.pushCalloutDismissedKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.timezoneWarnedHomeKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.windSpeedUnitKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.collapsedCardsKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.enabledKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastSentTokenKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.lastUpsertAtKey)
            UserDefaults.standard.removeObject(forKey: DeviceRegistration.pendingDeleteKey)
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_SEED_LIVE"),
           let data = try? JSONEncoder().encode([PreviewFixtures.cycling, PreviewFixtures.fishingLite]) {
            UserDefaults.standard.set(data, forKey: ActivityStore.storageKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // The opening sequence wraps the app (owner rulings 2026-11-11):
            // inside the one appearance modifier, so the splash renders in the
            // chosen appearance and never flips at the reveal, and inside the
            // rounded design, so the wordmark is SF Pro Rounded too.
            OpeningGate(plays: Self.playsOpening, router: PushRouter.shared) {
                DashboardView(viewModel: Self.makeViewModel(),
                              registration: Self.makeRegistration())
            }
            .fontDesign(.rounded)
            .preferredColorScheme(Self.uiTestAppearance)
        }
    }

    /// Cold launch only (this runs once per process); a push tap already
    /// routing skips it, as does a UI-test run that opts out.
    @MainActor
    private static var playsOpening: Bool {
        var uiTestSkip = false
        #if DEBUG
        uiTestSkip = ProcessInfo.processInfo.arguments.contains(OpeningPolicy.uiTestSkipArgument)
        #endif
        return OpeningPolicy.shouldPlay(coldLaunch: true,
                                        pushRoutePending: PushRouter.shared.focusActivityId != nil,
                                        uiTestSkip: uiTestSkip)
    }

    /// `UITEST_APPEARANCE=dark|light` in a UI-test mock run; nil (the system
    /// appearance) everywhere else, and always in release builds.
    private static var uiTestAppearance: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return ProcessInfo.uiTestAppearance(from: ProcessInfo.processInfo.arguments)
        }
        #endif
        return nil
    }

    @MainActor
    private static func makeViewModel() -> DashboardViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            let mode: MockRatingService.Mode =
                ProcessInfo.processInfo.arguments.contains("UITEST_MOCK_FAILURE") ? .failure : .success
            // Device zone pinned to the fixture's zone so mock runs stay
            // hermetic: no timezone-mismatch alert, sim-zone-independent clock.
            // UITEST_NOW=<ISO8601> pins the passed-hour clock so the 2026-06-19
            // fixture draws its live tier colours instead of passed-grey.
            let pinnedNow = ProcessInfo.uiTestNow(from: ProcessInfo.processInfo.arguments)
            return DashboardViewModel(api: MockRatingService(mode: mode),
                                      locationProvider: uiTestLocationProvider(),
                                      deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!,
                                      now: pinnedNow.map { pinned in { pinned } } ?? Date.init)
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
