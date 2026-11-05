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
}
