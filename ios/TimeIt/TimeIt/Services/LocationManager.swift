import Combine
import CoreLocation

/// Seam for injecting a fake location in tests.
@MainActor
protocol LocationProviding: AnyObject {
    var location: CLLocation? { get }
    /// Emits fix updates. `requestLocation()` resolves asynchronously, so a
    /// consumer that read `location` too early subscribes here to react when
    /// the real fix lands (e.g. rate a forecast that had no location yet).
    var locationPublisher: AnyPublisher<CLLocation?, Never> { get }
    /// #5c: distinguishes not-yet-asked from denied, so the "Enable location"
    /// CTA can fire the system prompt in the first case and deep-link to
    /// system Settings in the second.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Emits when authorization changes (e.g. the user returns from system
    /// Settings after granting access).
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    func requestLocation()
}

/// Thin CLLocationManager wrapper. Silent failure by design — when nothing
/// arrives, `location` stays nil and the ViewModel walks the rest of the
/// Active-location chain (#5c: last-resolved cache, then the no-location
/// empty state — never a substitute coordinate).
@MainActor
final class LocationManager: NSObject, ObservableObject, LocationProviding {
    static let shared = LocationManager()

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        $location.eraseToAnyPublisher()
    }

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent — the chain's later links (cache, empty state) cover denial,
        // Simulator, and timeouts.
    }
}
