import XCTest
@testable import TimeIt

/// Fresh-eyes note 4: city search returned one hit ("Springfield" → only
/// MO). The search now resolves every completion; `MapKitGeocoderService.rows`
/// is the pure mapping from resolved places to picker rows.
final class GeocodingResultsTests: XCTestCase {

    private func place(_ name: String, locality: String?, admin: String?, country: String?,
                       thoroughfare: String? = nil, lat: Double = 0, lon: Double = 0) -> PlaceCandidate {
        PlaceCandidate(name: name, locality: locality, administrativeArea: admin, country: country,
                       thoroughfare: thoroughfare, lat: lat, lon: lon)
    }

    func testEverySameNamedCityBecomesItsOwnRowInOrder() {
        let rows = MapKitGeocoderService.rows(from: [
            place("Springfield", locality: "Springfield", admin: "MO", country: "United States", lat: 37.2),
            place("Springfield", locality: "Springfield", admin: "IL", country: "United States", lat: 39.8),
            place("Springfield", locality: "Springfield", admin: "MA", country: "United States", lat: 42.1),
        ])
        XCTAssertEqual(rows.map(\.region), ["MO, United States", "IL, United States", "MA, United States"])
        XCTAssertEqual(rows.map(\.lat), [37.2, 39.8, 42.1])
    }

    func testStreetLevelMatchesAreDropped() {
        let rows = MapKitGeocoderService.rows(from: [
            place("Paris", locality: "Paris", admin: "Île-de-France", country: "France"),
            place("Paris Street", locality: "Al Jazirah Al Hamra", admin: "Ras al-Khaimah",
                  country: "United Arab Emirates", thoroughfare: "Paris Street"),
        ])
        XCTAssertEqual(rows.map(\.name), ["Paris"])
    }

    func testDuplicatePlacesCollapseAndCountryOnlyMatchesDrop() {
        let rows = MapKitGeocoderService.rows(from: [
            place("Dubai", locality: "Dubai", admin: "Dubai", country: "United Arab Emirates"),
            place("Dubai", locality: "Dubai", admin: "Dubai", country: "United Arab Emirates"),
            place("Greece", locality: nil, admin: nil, country: "Greece"),
        ])
        XCTAssertEqual(rows.count, 1)
    }
}
