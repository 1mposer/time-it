import XCTest
@testable import TimeIt

/// Pins `MapKitGeocoderService.regionLine` — the picker row's disambiguation
/// line (issue #15: a sub-city row must name its parent city, or "Bang O"
/// reads as Bangkok).
final class GeocodingRegionTests: XCTestCase {

    func testSubCityResultNamesItsParentCity() {
        let region = MapKitGeocoderService.regionLine(name: "Bang O",
                                                      locality: "Bangkok",
                                                      administrativeArea: "Bangkok",
                                                      country: "Thailand")
        XCTAssertEqual(region, "Bangkok, Thailand",
                       "the parent city leads; the duplicate admin area collapses")
    }

    func testCityLevelResultKeepsTheClassicAdminCountryLine() {
        let region = MapKitGeocoderService.regionLine(name: "Toronto",
                                                      locality: "Toronto",
                                                      administrativeArea: "Ontario",
                                                      country: "Canada")
        XCTAssertEqual(region, "Ontario, Canada",
                       "name == locality → the pre-#15 line is unchanged")
    }

    func testNeighborhoodResultNamesItsCityWithoutDuplication() {
        let region = MapKitGeocoderService.regionLine(name: "Dubai Marina",
                                                      locality: "Dubai",
                                                      administrativeArea: "Dubai",
                                                      country: "United Arab Emirates")
        XCTAssertEqual(region, "Dubai, United Arab Emirates")
    }

    func testNoDisambiguationAvailableReturnsNil() {
        let region = MapKitGeocoderService.regionLine(name: "Bangkok",
                                                      locality: "Bangkok",
                                                      administrativeArea: nil,
                                                      country: nil)
        XCTAssertNil(region, "an empty line stays nil — the row renders name only")
    }
}
