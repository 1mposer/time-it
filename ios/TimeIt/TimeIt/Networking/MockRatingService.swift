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

/// Location stand-in that never resolves — exercises the Dubai fallback.
@MainActor
final class StaticLocationProvider: LocationProviding {
    let location: CLLocation? = nil
    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    func requestLocation() {}
}

extension ForecastResponse {
    /// forecastStart 2026-06-19T12:00:00Z in Asia/Dubai = 16:00 local, so local
    /// day 0 spans indices 0..<8 and day 1 spans 8..<32. The first activity is
    /// windowed today (perfect), the second tomorrow (good), the rest null —
    /// covering both card-day paths.
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

        let ratings = activities.enumerated().map { offset, input in
            let days = (0..<7).map { dayIndex -> Day in
                if offset == 0, dayIndex == 0 {
                    return Day(dayIndex: 0, rating: "perfect", startIndex: 1, endIndex: 5, duration: 4)
                }
                if offset == 1, dayIndex == 1 {
                    return Day(dayIndex: 1, rating: "good", startIndex: 26, endIndex: 30, duration: 4)
                }
                return Day(dayIndex: dayIndex, rating: nil, startIndex: nil, endIndex: nil, duration: nil)
            }
            return ActivityRating(activityId: input.id,
                                  label: input.label,
                                  displayMetrics: input.displayMetrics,
                                  days: days)
        }

        return ForecastResponse(forecastStart: "2026-06-19T12:00:00Z",
                                timezone: "Asia/Dubai",
                                activities: ratings,
                                hours: hours)
    }
}
#endif
