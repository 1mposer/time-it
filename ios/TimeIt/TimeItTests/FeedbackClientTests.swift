import XCTest
@testable import TimeIt

/// The feedback client's session seam: the default session caps the request
/// timeout, and an injected session still wins.
final class FeedbackClientTests: XCTestCase {

    func testDefaultSessionCapsTheRequestTimeout() async {
        let client = FeedbackClient()

        let timeout = await client.session.configuration.timeoutIntervalForRequest

        XCTAssertEqual(timeout, 15, "worst-case send duration is the sheet's locked-UI ceiling")
    }

    func testBodyEncodesKindAsItsWireRawValue() throws {
        for (kind, wire) in [(FeedbackKind.suggestion, "suggestion"), (.liked, "liked")] {
            let body = FeedbackBody(deviceId: "d", message: "m", appVersion: "1.0",
                                    build: "9", iosVersion: "26.5", kind: kind)
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
            XCTAssertEqual(json?["kind"] as? String, wire)
            XCTAssertEqual(json?.count, 6, "five required strings + kind")
        }
    }

    func testInjectedSessionIsRespected() async {
        let custom = URLSession(configuration: .ephemeral)
        let client = FeedbackClient(session: custom)

        let session = await client.session

        XCTAssertTrue(session === custom, "the test seam must not be replaced by the configured default")
    }
}
