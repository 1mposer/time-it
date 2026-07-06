import XCTest
@testable import TimeIt

final class DayModelTests: XCTestCase {

    /// startIndex/endIndex are GLOBAL indices into hours[], not day-relative.
    /// A window on dayIndex >= 1 must decode with indices > 24 — this guards
    /// against any accidental per-day offset being introduced client-side.
    func testWindowOnLaterDayDecodesGlobalIndices() throws {
        let json = """
        { "dayIndex": 2, "rating": "good", "startIndex": 52, "endIndex": 55, "duration": 3 }
        """
        let day = try JSONDecoder().decode(Day.self, from: Data(json.utf8))
        XCTAssertEqual(day.dayIndex, 2)
        XCTAssertEqual(day.startIndex, 52)
        XCTAssertEqual(day.endIndex, 55)
        XCTAssertGreaterThan(day.startIndex ?? 0, 24, "indices must stay global — no per-day rebasing")
        XCTAssertEqual(day.duration, 3)
    }

    func testDayIdIsDayIndex() {
        XCTAssertEqual(Fixtures.makeDay(dayIndex: 4).id, 4)
    }
}
