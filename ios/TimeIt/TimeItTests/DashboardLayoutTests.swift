import XCTest
@testable import TimeIt

/// Build 10 POLISH item 2: the first Activity card rests at eye level — the
/// line the first-launch Add Activity capsule sits on.
final class DashboardLayoutTests: XCTestCase {
    typealias L = DashboardLayout

    /// iPhone 17 Pro: 62pt top safe area.
    private let safeTop: CGFloat = 62

    func testTheFirstLaunchCapsuleKeepsItsBuild9Spot() {
        // Build 9's empty-state header ended at 127; the hero padded 84.
        XCTAssertEqual(L.firstLaunchHeroTop(headerBottom: 127, safeTop: safeTop), 84)
    }

    func testTheFirstCardTopIsTheCapsuleTop() {
        for headerBottom: CGFloat in [180, 205, 230] {
            let cardTop = headerBottom + L.listTopInset(headerBottom: headerBottom, safeTop: safeTop, leadingHeight: 0)
            XCTAssertEqual(cardTop, safeTop + L.eyeLevel, "header bottom \(headerBottom)")
        }
        // The capsule's glass top, from the hero's own geometry.
        let emptyHeader: CGFloat = 127
        let capsuleTop = emptyHeader + L.firstLaunchListPadding
            + L.firstLaunchHeroTop(headerBottom: emptyHeader, safeTop: safeTop)
            + L.firstLaunchHeroPadding + GlassCapsule.addHitPadding
        XCTAssertEqual(capsuleTop, safeTop + L.eyeLevel)
    }

    func testTheCalloutSitsAboveTheCardInsideTheRoom() {
        // A 44pt resting bell + 10 gap fits; the card still lands at eye level.
        let inset = L.listTopInset(headerBottom: 205, safeTop: safeTop, leadingHeight: 54)
        XCTAssertEqual(205 + inset + 54, safeTop + L.eyeLevel)
    }

    func testATallHeaderNeverPushesTheListFurtherDown() {
        // AX text: the header already ends past eye level.
        XCTAssertEqual(L.listTopInset(headerBottom: 400, safeTop: safeTop, leadingHeight: 0),
                       Theme.Spacing.listBelowHeader)
        XCTAssertEqual(L.listTopInset(headerBottom: 205, safeTop: safeTop, leadingHeight: 200),
                       Theme.Spacing.listBelowHeader, "a full callout taller than the room")
        XCTAssertEqual(L.firstLaunchHeroTop(headerBottom: 400, safeTop: safeTop), 0)
    }
}
