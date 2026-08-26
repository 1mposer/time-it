import XCTest
@testable import TimeIt

final class DayModelTests: XCTestCase {

    /// startIndex/endIndex are global indices into hours[] — a later-day
    /// window must decode with indices > 24 (no per-day rebasing).
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
