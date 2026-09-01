import XCTest
@testable import TimeIt

/// AuthoredActivity is the client-side editable superset; it projects to the
/// wire ActivityInput by dropping UI-only fields.
final class AuthoredActivityProjectionTests: XCTestCase {

    private func encodeInput(_ activity: AuthoredActivity) throws -> [String: Any] {
        let data = try JSONEncoder().encode(activity.activityInput)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeAuthored(window: WindowSpec? = nil) -> AuthoredActivity {
        AuthoredActivity(id: "abc-123",
                         label: "Stargazing",
                         iconSymbol: "moon.stars.fill",
                         templateOrigin: "stargazing",
                         displayMetrics: ["temp", "cloudCover"],
                         thresholds: [
                            "temp": Threshold(min: 10, max: 30, required: true),
                            "cloudCover": Threshold(max: 20, required: true),
                         ],
                         window: window)
    }

    func testProjectionDropsUIOnlyFields() throws {
        let json = try encodeInput(makeAuthored())

        XCTAssertNil(json["iconSymbol"], "UI metadata must not reach the wire")
        XCTAssertNil(json["templateOrigin"], "UI metadata must not reach the wire")
        XCTAssertEqual(json["id"] as? String, "abc-123")
        XCTAssertEqual(json["label"] as? String, "Stargazing")
        XCTAssertEqual(json["displayMetrics"] as? [String], ["temp", "cloudCover"])
    }

    func testWholeDayActivityOmitsWindowKeyEntirely() throws {
        let json = try encodeInput(makeAuthored(window: nil))

        XCTAssertFalse(json.keys.contains("window"), "absent window = whole day; the key must be omitted, not null")
    }

    func testNocturnalWindowEncodesBothHours() throws {
        let json = try encodeInput(makeAuthored(window: WindowSpec(startHour: 22, endHour: 4)))

        let window = try XCTUnwrap(json["window"] as? [String: Any])
        XCTAssertEqual(window["startHour"] as? Int, 22)
        XCTAssertEqual(window["endHour"] as? Int, 4)
        XCTAssertEqual(window.count, 2, "window carries exactly startHour and endHour")
    }

    func testThresholdsProjectUnchanged() throws {
        let json = try encodeInput(makeAuthored())

        let thresholds = try XCTUnwrap(json["thresholds"] as? [String: [String: Any]])
        XCTAssertEqual(thresholds["temp"]?["min"] as? Double, 10)
        XCTAssertEqual(thresholds["temp"]?["max"] as? Double, 30)
        XCTAssertEqual(thresholds["temp"]?["required"] as? Bool, true)
        XCTAssertEqual(thresholds["cloudCover"]?["max"] as? Double, 20)
    }

    func testAuthoredActivityPersistsCodableRoundTrip() throws {
        let original = makeAuthored(window: WindowSpec(startHour: 22, endHour: 4))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AuthoredActivity.self, from: data)

        XCTAssertEqual(decoded, original, "local persistence round-trips the full editable model")
    }

    func testWindowlessActivityIsDormant() {
        XCTAssertTrue(makeAuthored(window: nil).isDormant)
        XCTAssertFalse(makeAuthored(window: WindowSpec(startHour: 6, endHour: 10)).isDormant)
        XCTAssertFalse(makeAuthored(window: WindowSpec(startHour: 22, endHour: 4)).isDormant)
    }

    func testIsNocturnalFollowsWrappedWindowOnly() {
        XCTAssertTrue(makeAuthored(window: WindowSpec(startHour: 22, endHour: 4)).isNocturnal)
        XCTAssertFalse(makeAuthored(window: WindowSpec(startHour: 6, endHour: 10)).isNocturnal, "same-day window is diurnal")
        XCTAssertFalse(makeAuthored(window: nil).isNocturnal, "whole-day is diurnal")
    }

}
