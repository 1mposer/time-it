import SwiftUI

@main
struct TimeItApp: App {
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
