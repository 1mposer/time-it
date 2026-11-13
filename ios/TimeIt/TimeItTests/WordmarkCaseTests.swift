import XCTest
@testable import TimeIt

/// The app's name is "Time it" — lowercase "it", like the opening's wordmark and
/// the approved Welcome frame (owner ruling 2026-11-13, post-release PR-009).
/// The home-screen name is the one copy site a reader cannot miss, so it pins the case.
final class WordmarkCaseTests: XCTestCase {
    func testTheHomeScreenNameReadsTimeItLowercase() {
        let bundle = Bundle(for: DashboardViewModel.self)
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        XCTAssertEqual(name, "Time it")
    }
}
