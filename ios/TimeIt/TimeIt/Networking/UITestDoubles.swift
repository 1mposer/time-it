#if DEBUG
import Combine
import CoreLocation
import Foundation

// The XCUI stand-ins for every seam the UI-test launch path swaps (wired in
// TimeItApp under UITEST_* launch arguments). DEBUG-only; never ships. The
// rating stand-in and its fixture live in MockRatingService.swift.

/// Fixed-fix location stand-in for UI tests: seeded with a coordinate, left
/// nil (the no-location path), or forced to .denied.
@MainActor
final class StaticLocationProvider: LocationProviding {
    let location: CLLocation?
    let authorizationStatus: CLAuthorizationStatus

    init(location: CLLocation? = nil, authorization: CLAuthorizationStatus? = nil) {
        self.location = location
        authorizationStatus = authorization ?? (location == nil ? .notDetermined : .authorizedWhenInUse)
    }

    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        Just(location).eraseToAnyPublisher()
    }

    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        Just(authorizationStatus).eraseToAnyPublisher()
    }

    func requestLocation() {}
    func requestAuthorization() {}
}

/// In-memory Keychain stand-in — UI-test opt-ins never touch the real one.
final class UITestKeychain: KeychainStoring {
    private var storage: [String: String] = [:]

    func read(key: String) -> String? {
        storage[key]
    }

    func write(key: String, value: String) {
        storage[key] = value
    }
}

/// Always-succeeding devices route — the XCUI opt-in flow needs no server.
struct UITestDevicesAPI: DeviceSnapshotSending {
    func putSnapshot(deviceId: String, body: DeviceSnapshotBody) async throws {}
    func deleteDevice(deviceId: String) async throws {}
}

/// Deterministic feedback route for XCUI: succeeds, or throws a 500 under
/// UITEST_FEEDBACK_FAIL.
struct UITestFeedbackAPI: SuggestionSending {
    let fails: Bool

    func send(_ body: FeedbackBody) async throws {
        if fails {
            throw APIError.serverError(statusCode: 500)
        }
    }
}

/// Deterministic permission prompt: grants unless UITEST_PUSH_DENY.
struct UITestPushAuthorizer: NotificationAuthorizing {
    let grants: Bool

    func requestAuthorization() async -> Bool {
        grants
    }
}
#endif
