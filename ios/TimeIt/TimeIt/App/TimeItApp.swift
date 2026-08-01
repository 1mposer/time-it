import CoreLocation
import SwiftUI

@main
struct TimeItApp: App {

    init() {
        #if DEBUG
        // UI tests start from the first-launch seed state: wipe persisted
        // authoring + preferences BEFORE any store singleton loads them.
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET") {
            UserDefaults.standard.removeObject(forKey: ActivityStore.storageKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.homeLocationKey)
            UserDefaults.standard.removeObject(forKey: PreferencesStore.lastResolvedLocationKey)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: Self.makeViewModel())
        }
    }

    @MainActor
    private static func makeViewModel() -> DashboardViewModel {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_MOCK_SUCCESS") {
            return DashboardViewModel(api: MockRatingService(mode: .success),
                                      locationProvider: uiTestLocationProvider())
        }
        if arguments.contains("UITEST_MOCK_FAILURE") {
            return DashboardViewModel(api: MockRatingService(mode: .failure),
                                      locationProvider: uiTestLocationProvider())
        }
        #endif
        return DashboardViewModel()
    }

    #if DEBUG
    /// UITEST_LOCATION feeds the mock provider a fixed fix so the card/header
    /// tests stay fed; without it the provider never resolves — the
    /// no-location path (#5c).
    @MainActor
    private static func uiTestLocationProvider() -> StaticLocationProvider {
        if ProcessInfo.processInfo.arguments.contains("UITEST_LOCATION") {
            return StaticLocationProvider(location: CLLocation(latitude: 25.2048, longitude: 55.2708))
        }
        return StaticLocationProvider()
    }
    #endif
}
