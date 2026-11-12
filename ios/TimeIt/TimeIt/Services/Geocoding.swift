import CoreLocation
import Foundation
import MapKit

/// Seam for city search: the real conformer wraps MapKit; UI tests
/// inject a canned result so the suite stays hermetic (no network geocoding).
protocol GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation]
}

/// One resolved place, reduced to the fields the picker row is built from —
/// a plain value so the mapping (`MapKitGeocoderService.rows`) is testable
/// without MapKit objects.
struct PlaceCandidate: Equatable {
    let name: String
    let locality: String?
    let administrativeArea: String?
    let country: String?
    let thoroughfare: String?
    let lat: Double
    let lon: Double

    init(name: String, locality: String?, administrativeArea: String?, country: String?,
         thoroughfare: String?, lat: Double, lon: Double) {
        self.name = name
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.country = country
        self.thoroughfare = thoroughfare
        self.lat = lat
        self.lon = lon
    }

    init(_ placemark: MKPlacemark) {
        self.init(name: placemark.name ?? placemark.locality ?? "",
                  locality: placemark.locality,
                  administrativeArea: placemark.administrativeArea,
                  country: placemark.country,
                  thoroughfare: placemark.thoroughfare,
                  lat: placemark.coordinate.latitude,
                  lon: placemark.coordinate.longitude)
    }
}

/// Worldwide city search via MapKit — no API key, no bundled city dataset.
/// A one-shot `MKLocalSearch` (and CLGeocoder) answers an ambiguous name
/// with ONE place ("Springfield" → only MO — probed 2026-11-12), so the
/// search asks `MKLocalSearchCompleter` for the candidate list (MO, IL, MA,
/// OR…) and resolves each completion to coordinates (note 4). The caller
/// debounces keystrokes, so one search runs per typing pause.
struct MapKitGeocoderService: GeocodingProviding {
    /// Completions resolved per search — bounds the parallel MapKit calls.
    static let maxResults = 10

    func geocode(_ query: String) async throws -> [SavedLocation] {
        let completions = await CompletionFetch().run(query)
        guard !completions.isEmpty else {
            // The completer has nothing (e.g. a single letter): the one-shot
            // search still finds its best match.
            return Self.rows(from: try await search(Self.addressRequest(query)))
        }
        let requests = completions.prefix(Self.maxResults).map { MKLocalSearch.Request(completion: $0) }
        // Resolved in parallel, kept in the completer's order; a failed
        // resolution drops its row, not the whole search.
        let resolved = await withTaskGroup(of: (Int, [PlaceCandidate]).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask { (index, (try? await search(request)) ?? []) }
            }
            var byIndex: [Int: [PlaceCandidate]] = [:]
            for await (index, places) in group { byIndex[index] = places }
            return byIndex
        }
        try Task.checkCancellation()
        return Self.rows(from: requests.indices.flatMap { resolved[$0] ?? [] })
    }

    private static func addressRequest(_ query: String) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        return request
    }

    private func search(_ request: MKLocalSearch.Request) async throws -> [PlaceCandidate] {
        do {
            return try await MKLocalSearch(request: request).start().mapItems.map { PlaceCandidate($0.placemark) }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    /// Resolved places → picker rows, in order. Localities only: a city
    /// result carries `locality`; bare street/POI and country matches are
    /// dropped, and the same place twice collapses to one row.
    static func rows(from places: [PlaceCandidate]) -> [SavedLocation] {
        var seen = Set<String>()
        return places.compactMap { place -> SavedLocation? in
            guard let locality = cityIdentity(locality: place.locality,
                                              administrativeArea: place.administrativeArea) else { return nil }
            // Street-level rows also carry a locality — "123 Main St" is not
            // a city. A thoroughfare marks them; neighborhoods ("Dubai
            // Marina") have none and stay.
            guard place.thoroughfare == nil else { return nil }
            // The place's own name keeps neighborhood-level queries ("Dubai
            // Marina") honest — locality alone would flatten them to the
            // parent city, as the old CLGeocoder path did.
            let name = place.name.isEmpty ? locality : place.name
            let region = regionLine(name: name,
                                    locality: locality,
                                    administrativeArea: place.administrativeArea,
                                    country: place.country)
            guard seen.insert("\(name)|\(region ?? "")").inserted else { return nil }
            return SavedLocation(name: name, lat: place.lat, lon: place.lon, region: region)
        }
    }

    /// The row's city identity: the locality, or the administrative area for
    /// places Apple models at province level with no locality (Bangkok,
    /// Hong Kong) — a bare locality guard filters those cities out entirely.
    /// nil drops the row (country-level matches carry neither).
    static func cityIdentity(locality: String?, administrativeArea: String?) -> String? {
        locality ?? administrativeArea
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

/// `MKLocalSearchCompleter` as a one-shot async call: a fresh completer per
/// search, resumed exactly once — the first results, an error, the timeout
/// or the caller's cancellation, whichever lands first (the delegate can
/// fire repeatedly).
@MainActor
private final class CompletionFetch: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?

    func run(_ query: String, timeout: TimeInterval = 3) async -> [MKLocalSearchCompletion] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                completer.delegate = self
                completer.resultTypes = .address
                completer.queryFragment = query
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self?.finish([])
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish([]) }
        }
    }

    private func finish(_ results: [MKLocalSearchCompletion]) {
        guard let continuation else { return }
        self.continuation = nil
        completer.cancel()
        continuation.resume(returning: results)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.finish(results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.finish([]) }
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

/// Hermetic geocoder for XCUI tests: echoes the query as a Dubai-area
/// result, plus a second row so the picker's full list is provable (note 4).
/// The echo stays first for every `pickCity` caller.
struct MockGeocoderService: GeocodingProviding {
    func geocode(_ query: String) async throws -> [SavedLocation] {
        [SavedLocation(name: query, lat: 25.08, lon: 55.14, region: "United Arab Emirates"),
         SavedLocation(name: query, lat: 24.45, lon: 54.38, region: "Abu Dhabi, United Arab Emirates")]
    }
}
#endif
