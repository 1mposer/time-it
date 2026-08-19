import XCTest
@testable import TimeIt

/// The feedback client's session seam: the default session caps the request
/// timeout (the sheet disables Cancel mid-send, so URLSession.shared's 60s
/// default is the wrong worst case — a timeout URLError lands in the
/// existing non-204 retry path), and an injected session still wins.
final class FeedbackClientTests: XCTestCase {

    func testDefaultSessionCapsTheRequestTimeout() async {
        let client = FeedbackClient()

        let timeout = await client.session.configuration.timeoutIntervalForRequest

        XCTAssertEqual(timeout, 15, "worst-case send duration is the sheet's locked-UI ceiling")
    }

    func testInjectedSessionIsRespected() async {
        let custom = URLSession(configuration: .ephemeral)
        let client = FeedbackClient(session: custom)

        let session = await client.session

        XCTAssertTrue(session === custom, "the test seam must not be replaced by the configured default")
    }
}
