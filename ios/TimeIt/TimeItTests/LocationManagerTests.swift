import CoreLocation
import XCTest
@testable import TimeIt

/// Which `didFailWithError` errors the manager publishes as a failed fix.
final class LocationManagerTests: XCTestCase {

    func testADenialIsNotPublishedAsAFailedFix() {
        XCTAssertFalse(LocationManager.isReportableFailure(CLError(.denied)),
                       "the authorization status carries a denial — it is never retried")
    }

    func testAMissingFixIsPublished() {
        XCTAssertTrue(LocationManager.isReportableFailure(CLError(.locationUnknown)))
        XCTAssertTrue(LocationManager.isReportableFailure(CLError(.network)))
    }

    func testANonLocationErrorIsPublished() {
        XCTAssertTrue(LocationManager.isReportableFailure(URLError(.timedOut)))
    }
}
