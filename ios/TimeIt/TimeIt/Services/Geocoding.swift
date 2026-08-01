import CoreLocation
import Foundation
import MapKit

/// Seam for the city search (#5b §5, upgraded in #5c): the real conformer
/// wraps MKLocalSearch; UI tests inject a canned result so the suite stays
/// hermetic (no network geocoding).
protocol GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation]
}

/// #5c: worldwide city search via MKLocalSearch — no API key, no bundled
/// city dataset. Deliberately NOT MKLocalSearchCompleter: that API is
/// delegate-driven (streams incremental results) and cannot conform to this
/// one-shot seam — the caller debounces keystrokes instead, which gives the
/// same as-you-type UX.
struct MapKitGeocoderService: GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
        // Filter to localities: a city result carries `locality`; bare
        // street/POI matches are dropped. Multiple addresses in one city
        // collapse to a single row.
        var seen = Set<String>()
        return response.mapItems.compactMap { item -> SavedLocation? in
            let placemark = item.placemark
            guard let locality = placemark.locality else { return nil }
            // Street-level rows also carry a locality — "123 Main St" is not
            // a city (audit F4). A thoroughfare marks them; neighborhoods
            // ("Dubai Marina") have none and stay.
            guard placemark.thoroughfare == nil else { return nil }
            // placemark.name keeps neighborhood-level queries ("Dubai
            // Marina") honest — locality alone would flatten them to the
            // parent city (and regress the #5b CLGeocoder behavior).
            let name = placemark.name ?? locality
            let region = [placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            guard seen.insert("\(name)|\(region)").inserted else { return nil }
            return SavedLocation(name: name,
                                 lat: placemark.coordinate.latitude,
                                 lon: placemark.coordinate.longitude,
                                 region: region.isEmpty ? nil : region)
        }
    }
}

/// Resolves the geocoder for views that don't get one injected.
enum GeocoderFactory {
    /// UI tests inject a hermetic geocoder via the mock launch args; everyone
    /// else searches for real.
    static func makeDefault() -> GeocodingProviding {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return MockGeocoderService()
        }
        #endif
        return MapKitGeocoderService()
    }
}

#if DEBUG
extension ProcessInfo {
    /// True when the XCUI suite launched us with a hermetic mock backend —
    /// the one definition both the app factory and the geocoder factory read.
    var isUITestMockRun: Bool {
        arguments.contains("UITEST_MOCK_SUCCESS") || arguments.contains("UITEST_MOCK_FAILURE")
    }
}

/// Hermetic geocoder for XCUI tests: echoes the query as a Dubai-area result.
struct MockGeocoderService: GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation] {
        [SavedLocation(name: query, lat: 25.08, lon: 55.14, region: "United Arab Emirates")]
    }
}
#endif
