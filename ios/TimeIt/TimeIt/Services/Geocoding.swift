import CoreLocation
import Foundation
import MapKit

/// Seam for city search: the real conformer wraps MKLocalSearch; UI tests
/// inject a canned result so the suite stays hermetic (no network geocoding).
protocol GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation]
}

/// Worldwide city search via MKLocalSearch — no API key, no bundled city
/// dataset. Deliberately NOT MKLocalSearchCompleter: that API is
/// delegate-driven (streams incremental results) and can't conform to this
/// one-shot seam — the caller debounces keystrokes instead, for the same
/// as-you-type UX.
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
        // collapse to one row.
        var seen = Set<String>()
        return response.mapItems.compactMap { item -> SavedLocation? in
            let placemark = item.placemark
            guard let locality = placemark.locality else { return nil }
            // Street-level rows also carry a locality — "123 Main St" is not
            // a city. A thoroughfare marks them; neighborhoods ("Dubai
            // Marina") have none and stay.
            guard placemark.thoroughfare == nil else { return nil }
            // placemark.name keeps neighborhood-level queries ("Dubai
            // Marina") honest — locality alone would flatten them to the
            // parent city, as the old CLGeocoder path did.
            let name = placemark.name ?? locality
            let region = Self.regionLine(name: name,
                                         locality: locality,
                                         administrativeArea: placemark.administrativeArea,
                                         country: placemark.country)
            guard seen.insert("\(name)|\(region ?? "")").inserted else { return nil }
            return SavedLocation(name: name,
                                 lat: placemark.coordinate.latitude,
                                 lon: placemark.coordinate.longitude,
                                 region: region)
        }
    }

    /// The picker row's disambiguation line. A sub-city result carries its
    /// parent city ("Bang O" → "Bangkok, Thailand") — without it, a
    /// subdistrict row reads as the city the user searched for.
    static func regionLine(name: String,
                           locality: String,
                           administrativeArea: String?,
                           country: String?) -> String? {
        var parts: [String] = []
        for part in [locality, administrativeArea, country] {
            guard let part, part != name, !parts.contains(part) else { continue }
            parts.append(part)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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
    /// the one definition both the app factory and geocoder factory read.
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
