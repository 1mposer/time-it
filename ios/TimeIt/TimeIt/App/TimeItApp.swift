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
                                      locationProvider: StaticLocationProvider())
        }
        if arguments.contains("UITEST_MOCK_FAILURE") {
            return DashboardViewModel(api: MockRatingService(mode: .failure),
                                      locationProvider: StaticLocationProvider())
        }
        #endif
        return DashboardViewModel()
    }
}
