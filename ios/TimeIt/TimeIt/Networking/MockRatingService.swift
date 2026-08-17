#if DEBUG
import Combine
import CoreLocation
import Foundation

/// Hermetic backend stand-in for UI tests (launch arguments UITEST_MOCK_SUCCESS /
/// UITEST_MOCK_FAILURE) — keeps the acceptance suite deterministic with no
/// Node server or Meteosource key. DEBUG-only; never ships.
struct MockRatingService: RatingFetching {
    enum Mode {
        case success
        case failure
    }

    let mode: Mode

    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse {
        switch mode {
        case .failure:
            throw APIError.providerUnavailable
        case .success:
            return .uiTestFixture(for: activities)
        }
    }
}

/// Fixed-fix location stand-in for UI tests: seeded with a coordinate via
/// UITEST_LOCATION, left nil to exercise the #5c no-location path, or forced
/// to .denied via UITEST_LOCATION_DENIED for the fresh-install-denied case.
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

/// Deterministic permission prompt: grants unless UITEST_PUSH_DENY.
struct UITestPushAuthorizer: NotificationAuthorizing {
    let grants: Bool

    func requestAuthorization() async -> Bool {
        grants
    }
}

extension ForecastResponse {
    /// forecastStart 2026-06-19T00:00:00Z in Asia/Dubai = 4am local, so local
    /// day 0 spans indices 0..<20 (4am → midnight), day 1 spans 20..<44 and
    /// day 2 the partial 44..<56. Range-CONSISTENT with the seeded templates
    /// (spec 14 — the card slice paints the authored Range):
    /// - activity 0 (cycling, 6–10am): Perfect today across exactly its range
    ///   (indices 2..<6 → "Today · 6–10am").
    /// - activity 1 (fishing-lite, 3–7pm): NOTHING today (the all-red card)
    ///   and a Good window tomorrow (indices 35..<39), which the card must
    ///   NOT roll forward to (ADR-0004 amendment 2026-07-20) — the detail
    ///   still shows it.
    /// - a WRAPPED-window activity (stargazing, 10pm–4am) gets 6 NIGHT
    ///   buckets, Perfect tonight 10pm–2am (indices 18..<22 → "Tonight ·
    ///   10pm–2am") — the per-activity days.length contract at the wire.
    /// - anything else: all-null days.
    static func uiTestFixture(for activities: [ActivityInput]) -> ForecastResponse {
        let hours = (0..<56).map { index in
            HourlyWeather(index: index,
                          temp: 24,
                          humidity: 40,
                          visibility: 10,
                          uV: 3,
                          windSpeed: 10,
                          rainFall: 0,
                          cloudCover: 15,
                          moon: ["waxing crescent"],
                          dustAlert: false,
                          seaWarning: false,
                          darkness: 0,
                          douglasScale: 0,
                          swellHeight: 0,
                          swellLength: 0,
                          tide: 0)
        }

        let ratings = activities.enumerated().map { offset, input -> ActivityRating in
            let nocturnal = input.window?.isWrapped == true
            let days = (0..<(nocturnal ? 6 : 7)).map { dayIndex -> Day in
                if nocturnal, dayIndex == 0 {
                    return Day(dayIndex: 0, rating: "perfect", startIndex: 18, endIndex: 22, duration: 4)
                }
                if !nocturnal, offset == 0, dayIndex == 0 {
                    return Day(dayIndex: 0, rating: "perfect", startIndex: 2, endIndex: 6, duration: 4)
                }
                if !nocturnal, offset == 1, dayIndex == 1 {
                    return Day(dayIndex: 1, rating: "good", startIndex: 35, endIndex: 39, duration: 4)
                }
                return Day(dayIndex: dayIndex, rating: nil, startIndex: nil, endIndex: nil, duration: nil)
            }
            return ActivityRating(activityId: input.id,
                                  label: input.label,
                                  displayMetrics: input.displayMetrics,
                                  days: days)
        }

        return ForecastResponse(forecastStart: "2026-06-19T00:00:00Z",
                                timezone: "Asia/Dubai",
                                activities: ratings,
                                hours: hours)
    }
}
#endif
