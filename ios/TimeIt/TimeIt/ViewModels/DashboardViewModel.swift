import CoreLocation
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var forecast: ForecastResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// True when the last failure is worth retrying (502 / unreachable server),
    /// as opposed to a server defect (500). Drives the error view's framing.
    private(set) var isTransientError = false

    /// Fallback when no device location is available (Simulator, denied, timeout).
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 25.1627, longitude: 55.2077) // Dubai

    private let api: RatingFetching
    private let locationProvider: LocationProviding
    private let activities: [ActivityInput]

    init(api: RatingFetching = APIClient.shared,
         locationProvider: LocationProviding? = nil,
         activities: [ActivityInput] = SeedTemplates.all) {
        self.api = api
        // Resolved here, not as a default argument — LocationManager.shared is
        // main-actor-isolated and default arguments evaluate in the caller's context.
        self.locationProvider = locationProvider ?? LocationManager.shared
        self.activities = activities
    }

    var timeDeriver: TimeDeriver? {
        forecast.flatMap { TimeDeriver(forecastStart: $0.forecastStart, timezone: $0.timezone) }
    }

    func loadForecast() async {
        locationProvider.requestLocation()

        isLoading = true
        errorMessage = nil
        isTransientError = false

        let coordinate = locationProvider.location?.coordinate ?? Self.fallbackCoordinate
        do {
            forecast = try await api.fetchRatings(lat: coordinate.latitude,
                                                  lon: coordinate.longitude,
                                                  activities: activities)
        } catch let error as APIError {
            errorMessage = error.userMessage
            isTransientError = error.isTransient
        } catch {
            errorMessage = "Unable to reach the server. Check that it's running and try again."
            isTransientError = true
        }
        isLoading = false
    }

    /// The card's day: soonest-actionable, NOT best — the first day with any
    /// rating; a later Perfect never beats an earlier Good (ADR-0004).
    func cardDay(for activity: ActivityRating) -> Day? {
        activity.days.first { $0.rating != nil }
    }

    /// The hour at the day's window start — chips read their values here.
    /// `startIndex` is a global index into hours[]; no per-day offset math.
    func windowStartHour(for day: Day) -> HourlyWeather? {
        guard let startIndex = day.startIndex,
              let hours = forecast?.hours,
              hours.indices.contains(startIndex) else {
            return nil
        }
        return hours[startIndex]
    }

    /// The half-open slice `hours[startIndex..<endIndex]` for a day's Window;
    /// empty when indices are absent or out of range.
    func windowHours(for day: Day) -> [HourlyWeather] {
        guard let startIndex = day.startIndex,
              let endIndex = day.endIndex,
              let hours = forecast?.hours,
              startIndex >= 0, startIndex < endIndex, endIndex <= hours.count else {
            return []
        }
        return Array(hours[startIndex..<endIndex])
    }
}
