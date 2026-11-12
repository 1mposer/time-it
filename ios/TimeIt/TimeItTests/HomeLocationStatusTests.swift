import CoreLocation
import XCTest
@testable import TimeIt

/// Fresh-eyes notes 3 + 8: Settings' Home row tells the truth about location
/// access, and "Use current location" can't wipe a picked city while
/// location is off.
final class HomeLocationStatusTests: XCTestCase {

    func testAPickedCityNamesTheRowWhateverTheAccess() {
        XCTAssertEqual(HomeLocationStatus.label(homeName: "Dubai", authorization: .denied), "Dubai")
        XCTAssertEqual(HomeLocationStatus.label(homeName: "Dubai", authorization: .authorizedWhenInUse), "Dubai")
    }

    func testDeniedOrRestrictedWithNoCityReadsLocationOff() {
        XCTAssertEqual(HomeLocationStatus.label(homeName: nil, authorization: .denied), "Location off")
        XCTAssertEqual(HomeLocationStatus.label(homeName: nil, authorization: .restricted), "Location off")
    }

    func testAllowedOrNotYetAskedWithNoCityUsesCurrentLocation() {
        XCTAssertEqual(HomeLocationStatus.label(homeName: nil, authorization: .authorizedWhenInUse),
                       "Using current location")
        XCTAssertEqual(HomeLocationStatus.label(homeName: nil, authorization: .notDetermined),
                       "Using current location")
    }

    func testUseCurrentLocationIsOfferedOnlyWhenLocationCanBeUsed() {
        XCTAssertFalse(HomeLocationStatus.canUseCurrentLocation(authorization: .denied))
        XCTAssertFalse(HomeLocationStatus.canUseCurrentLocation(authorization: .restricted))
        XCTAssertTrue(HomeLocationStatus.canUseCurrentLocation(authorization: .authorizedWhenInUse))
        XCTAssertTrue(HomeLocationStatus.canUseCurrentLocation(authorization: .notDetermined))
    }
}
