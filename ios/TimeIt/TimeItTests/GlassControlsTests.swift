import XCTest
@testable import TimeIt

/// The glass controls slice (owner ruling 2026-11-04): every glass control
/// is at least the HIG 44pt target, and the cap state dims to half strength.
final class GlassControlsTests: XCTestCase {

    func testGlassCapsulesAreTheHIGMinimumTarget() {
        XCTAssertEqual(GlassCapsule.height, 44, "a primary glass capsule is its own 44pt target")
    }

    func testHeaderGearIsA44ptGlassCircle() {
        XCTAssertEqual(HeaderView.gearDiameter, 44, "the header gear grew from 34pt to the HIG 44pt")
    }

    func testTheActivityLimitCapsuleDimsToHalf() {
        XCTAssertEqual(GlassCapsule.disabledOpacity, 0.5)
    }

    // MARK: Mini edits (owner report 2026-11-05)

    func testTheHeaderGearIsClearGlassNotRegular() {
        XCTAssertEqual(HeaderView.gearGlassStyle, .clear,
                       "regular glass over the light band reads as a white disc")
    }

    func testTheAddCapsuleIsOneNotchSmaller() {
        XCTAssertEqual(GlassCapsule.addHeight, 40, "the visible Add capsule drops from 44 to 40")
        XCTAssertEqual(GlassCapsule.addHorizontalPadding, 18)
    }

    func testTheAddCapsuleKeepsThe44ptHitTarget() {
        // 40 visible + 2 above + 2 below = the HIG 44.
        XCTAssertEqual(GlassCapsule.addHeight + 2 * GlassCapsule.addHitPadding, 44)
        XCTAssertEqual(GlassCapsule.addHitPadding, 2)
    }

    func testTheRevealSpringIsCriticallyDamped() {
        // A tap throws nothing, so the reveal never overshoots.
        XCTAssertEqual(Theme.Motion.revealDuration, 0.35)
        XCTAssertEqual(Theme.Motion.revealBounce, 0)
    }
}
