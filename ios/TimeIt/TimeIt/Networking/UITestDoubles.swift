#if DEBUG
import Combine
import CoreLocation
import Foundation
import SwiftUI

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

extension ProcessInfo {
    /// The UI-test clock pin: the instant in a `UITEST_NOW=<ISO8601>` launch
    /// argument (e.g. `UITEST_NOW=2026-06-19T00:30:00Z`); nil when absent or
    /// malformed. Read only in a UI-test mock run.
    static func uiTestNow(from arguments: [String]) -> Date? {
        let prefix = "UITEST_NOW="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return ISO8601DateFormatter().date(from: String(argument.dropFirst(prefix.count)))
    }

    /// The UI-test appearance pin: `UITEST_APPEARANCE=dark` / `=light` → that
    /// scheme; nil (follow the system) when absent or any other value. Read
    /// only in a UI-test mock run.
    static func uiTestAppearance(from arguments: [String]) -> ColorScheme? {
        let prefix = "UITEST_APPEARANCE="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        switch argument.dropFirst(prefix.count) {
        case "dark": return .dark
        case "light": return .light
        default: return nil
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
