import CoreLocation
import Foundation

/// Seam for the Settings home-location search (#5b §5): the real conformer
/// wraps CLGeocoder; UI tests inject a canned result so the suite stays
/// hermetic (no network geocoding).
protocol GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation]
}

struct CLGeocoderService: GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation] {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        return placemarks.compactMap { placemark in
            guard let coordinate = placemark.location?.coordinate else { return nil }
            let name = placemark.name ?? placemark.locality ?? query
            return SavedLocation(name: name, lat: coordinate.latitude, lon: coordinate.longitude)
        }
    }
}

#if DEBUG
/// Hermetic geocoder for XCUI tests: echoes the query as a Dubai-area result.
struct MockGeocoderService: GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation] {
        [SavedLocation(name: query, lat: 25.08, lon: 55.14)]
    }
}
#endif
