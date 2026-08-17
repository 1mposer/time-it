import XCTest
@testable import TimeIt

/// Push receipt routing (spec §3). The detector payload's custom keys land at
/// the ROOT of userInfo beside "aps" (apns2 `data:` merge) — pinned here.
@MainActor
final class PushRouterTests: XCTestCase {

    func testPerfectWindowPayloadFocusesTheNamedActivity() {
        let router = PushRouter()

        router.handle(userInfo: ["aps": ["alert": ["title": "Perfect Cycling window"]],
                                 "type": "perfectWindow",
                                 "activityId": "cycling",
                                 "bucketDate": "2026-08-17"])

        XCTAssertEqual(router.focusActivityId, "cycling")
    }

    func testDigestPayloadWithoutTypeJustOpensTheDashboard() {
        let router = PushRouter()

        router.handle(userInfo: ["aps": ["alert": ["title": "Your Time It digest"]]])

        XCTAssertNil(router.focusActivityId, "default open — no deeper routing in v1")
    }

    func testUnknownTypeOrMissingActivityIdIsIgnored() {
        let router = PushRouter()

        router.handle(userInfo: ["type": "somethingElse", "activityId": "cycling"])
        XCTAssertNil(router.focusActivityId)

        router.handle(userInfo: ["type": "perfectWindow"])
        XCTAssertNil(router.focusActivityId)
    }
}
