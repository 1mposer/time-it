#if DEBUG
import XCTest
@testable import TimeIt

/// `UITEST_NOW=<ISO8601>` — the UI-test clock pin's launch-argument parse.
final class UITestClockTests: XCTestCase {

    func testParsesAValidISO8601Instant() {
        let now = ProcessInfo.uiTestNow(from: ["UITEST_MOCK_SUCCESS", "UITEST_NOW=2026-06-19T00:30:00Z"])
        XCTAssertEqual(now, ISO8601DateFormatter().date(from: "2026-06-19T00:30:00Z"))
    }

    func testMissingArgumentIsNil() {
        XCTAssertNil(ProcessInfo.uiTestNow(from: ["UITEST_MOCK_SUCCESS", "UITEST_RESET"]))
        XCTAssertNil(ProcessInfo.uiTestNow(from: []))
    }

    func testMalformedValueIsNil() {
        XCTAssertNil(ProcessInfo.uiTestNow(from: ["UITEST_NOW=tomorrow"]))
        XCTAssertNil(ProcessInfo.uiTestNow(from: ["UITEST_NOW="]))
        XCTAssertNil(ProcessInfo.uiTestNow(from: ["UITEST_NOW"]), "the bare flag carries no instant")
    }
}
#endif
