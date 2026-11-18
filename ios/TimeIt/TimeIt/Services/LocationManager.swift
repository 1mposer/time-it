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
    /// Distinguishes not-yet-asked from denied, so the "Enable location" CTA
    /// can fire the system prompt in the first case and deep-link to system
    /// Settings in the second.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Emits when authorization changes (e.g. the user returns from system
    /// Settings after granting access).
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    /// Emits when a requested fix fails (a denial excluded — the
    /// authorization status already says that), so the consumer can retry
    /// and offer a way forward instead of waiting on a fix that won't come.
    var locationFailurePublisher: AnyPublisher<Void, Never> { get }
    /// Ask for a fresh fix. Fix-only — never triggers the permission prompt;
    /// callers check `authorizationStatus` first (the prompt belongs to the
    /// "Enable location" CTA, not to every load).
    func requestLocation()
    /// Fire the When-In-Use permission prompt. Only the CTA calls this — a
    /// no-op once the status is determined.
    func requestAuthorization()
}

/// Thin CLLocationManager wrapper. When nothing arrives, `location` stays
/// nil and the ViewModel walks the rest of the Active-location chain
/// (last-resolved cache, then the no-location state — never a substitute
/// coordinate); a failed fix is published so the ViewModel can retry.
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

    var locationFailurePublisher: AnyPublisher<Void, Never> {
        failures.eraseToAnyPublisher()
    }

    private let failures = PassthroughSubject<Void, Never>()
    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
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
        guard Self.isReportableFailure(error) else { return }
        Task { @MainActor in
            self.failures.send()
        }
    }

    /// A denial is not a failed fix to retry — the authorization status
    /// carries it. Everything else (no fix yet, network, timeout) is.
    nonisolated static func isReportableFailure(_ error: Error) -> Bool {
        (error as? CLError)?.code != .denied
    }
}
