import CoreLocation

/// Seam for injecting a fake location in tests.
@MainActor
protocol LocationProviding: AnyObject {
    var location: CLLocation? { get }
    func requestLocation()
}

/// Thin CLLocationManager wrapper. Silent failure by design — when nothing
/// arrives, `location` stays nil and the ViewModel falls back to Dubai.
@MainActor
final class LocationManager: NSObject, ObservableObject, LocationProviding {
    static let shared = LocationManager()

    @Published private(set) var location: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            self.location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — the Dubai fallback covers denial, Simulator, and timeouts.
    }
}
