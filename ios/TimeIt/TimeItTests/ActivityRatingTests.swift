import XCTest
@testable import TimeIt

final class ActivityRatingTests: XCTestCase {

    func testDecodesSevenDayActivity() throws {
        let activity = try JSONDecoder().decode(ActivityRating.self,
                                                from: Data(Fixtures.activityJSON(dayCount: 7).utf8))
        XCTAssertEqual(activity.days.count, 7, "days.count must come from the payload, never be assumed")
        XCTAssertEqual(activity.activityId, "cycling")
        XCTAssertEqual(activity.label, "Cycling")
        XCTAssertEqual(activity.displayMetrics, ["temp", "windSpeed"])
    }

    func testDecodesEightDayActivity() throws {
        let activity = try JSONDecoder().decode(ActivityRating.self,
                                                from: Data(Fixtures.activityJSON(dayCount: 8).utf8))
        XCTAssertEqual(activity.days.count, 8, "an 8-day activity must decode all 8 days — 7 is not a fixed count")
    }

    func testDayIndexIsDenseAndContiguous() throws {
        let activity = try JSONDecoder().decode(ActivityRating.self,
                                                from: Data(Fixtures.activityJSON(dayCount: 8).utf8))
        for (i, day) in activity.days.enumerated() {
            XCTAssertEqual(day.dayIndex, i)
        }
    }

    func testNullRatingDayDecodesWithAbsentIndices() throws {
        let day = try JSONDecoder().decode(Day.self, from: Data(Fixtures.nullDayJSON.utf8))
        XCTAssertNil(day.rating)
        XCTAssertNil(day.startIndex)
        XCTAssertNil(day.endIndex)
        XCTAssertNil(day.duration)
    }

    func testWindowedDayDecodesIndicesPresent() throws {
        let day = try JSONDecoder().decode(Day.self, from: Data(Fixtures.windowedDayJSON.utf8))
        XCTAssertEqual(day.rating, "perfect")
        XCTAssertEqual(day.startIndex, 3)
        XCTAssertEqual(day.endIndex, 9)
        XCTAssertEqual(day.duration, 6)
    }

    func testHasWindow() {
        XCTAssertTrue(Fixtures.makeDay(dayIndex: 0, rating: "perfect", startIndex: 1, endIndex: 3, duration: 2).hasWindow)
        XCTAssertTrue(Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 1, endIndex: 3, duration: 2).hasWindow)
        XCTAssertFalse(Fixtures.makeDay(dayIndex: 0).hasWindow)
    }

    func testRatingDisplay() {
        XCTAssertEqual(Fixtures.makeDay(dayIndex: 0, rating: "perfect", startIndex: 1, endIndex: 3, duration: 2).ratingDisplay, "Perfect")
        XCTAssertEqual(Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 1, endIndex: 3, duration: 2).ratingDisplay, "Good")
        XCTAssertEqual(Fixtures.makeDay(dayIndex: 0).ratingDisplay, "No Window")
    }

    func testIdAliasesActivityId() throws {
        let activity = try JSONDecoder().decode(ActivityRating.self,
                                                from: Data(Fixtures.activityJSON(id: "fishing-lite", label: "Fishing Lite", dayCount: 7).utf8))
        XCTAssertEqual(activity.id, "fishing-lite")
    }
}
