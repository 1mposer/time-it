#if DEBUG
import SwiftUI
import XCTest
@testable import TimeIt

/// `UITEST_APPEARANCE=dark|light` — the UI-test appearance pin's parse.
final class UITestAppearanceTests: XCTestCase {

    func testDarkAndLight() {
        XCTAssertEqual(ProcessInfo.uiTestAppearance(from: ["UITEST_MOCK_SUCCESS", "UITEST_APPEARANCE=dark"]), .dark)
        XCTAssertEqual(ProcessInfo.uiTestAppearance(from: ["UITEST_APPEARANCE=light"]), .light)
    }

    func testAbsentFollowsTheSystem() {
        XCTAssertNil(ProcessInfo.uiTestAppearance(from: ["UITEST_MOCK_SUCCESS", "UITEST_NOW=2026-06-19T00:30:00Z"]))
        XCTAssertNil(ProcessInfo.uiTestAppearance(from: []))
    }

    func testUnknownValueFollowsTheSystem() {
        XCTAssertNil(ProcessInfo.uiTestAppearance(from: ["UITEST_APPEARANCE=Dark"]), "case-sensitive, like the other pins")
        XCTAssertNil(ProcessInfo.uiTestAppearance(from: ["UITEST_APPEARANCE="]))
        XCTAssertNil(ProcessInfo.uiTestAppearance(from: ["UITEST_APPEARANCE"]))
    }
}
#endif
