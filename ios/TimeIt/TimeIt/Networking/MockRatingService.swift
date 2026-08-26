#if DEBUG
import Combine
import CoreLocation
import Foundation

/// Hermetic backend stand-in for UI tests — deterministic, no Node server or
/// API key needed. DEBUG-only; never ships.
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

extension ForecastResponse {
    /// Fixture starting 2026-06-19T00:00:00Z (= 4am in Asia/Dubai; day 0 =
    /// indices 0..<20). Consistent with the seeded templates: activity 0 is
    /// Perfect today across its range, activity 1 has nothing today and a
    /// Good window tomorrow, a wrapped-window activity gets 6 night buckets
    /// with Perfect tonight; anything else all-null days. UI tests assert
    /// these exact indices.
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
