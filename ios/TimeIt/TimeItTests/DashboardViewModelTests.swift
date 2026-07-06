import XCTest
import CoreLocation
@testable import TimeIt

// MARK: - Fakes

final class FakeRatingService: RatingFetching {
    var result: Result<ForecastResponse, Error>
    var onFetch: (@MainActor () -> Void)?
    private(set) var capturedLat: Double?
    private(set) var capturedLon: Double?
    private(set) var capturedActivities: [ActivityInput]?

    init(result: Result<ForecastResponse, Error>) {
        self.result = result
    }

    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse {
        capturedLat = lat
        capturedLon = lon
        capturedActivities = activities
        if let onFetch {
            await MainActor.run { onFetch() }
        }
        return try result.get()
    }
}

@MainActor
final class FakeLocationProvider: LocationProviding {
    var location: CLLocation?
    private(set) var requestLocationCalled = false

    init(location: CLLocation? = nil) {
        self.location = location
    }

    func requestLocation() {
        requestLocationCalled = true
    }
}

// MARK: - Tests

@MainActor
final class DashboardViewModelTests: XCTestCase {

    private func makeVM(result: Result<ForecastResponse, Error>,
                        location: CLLocation? = nil) -> (DashboardViewModel, FakeRatingService, FakeLocationProvider) {
        let api = FakeRatingService(result: result)
        let locationProvider = FakeLocationProvider(location: location)
        let vm = DashboardViewModel(api: api, locationProvider: locationProvider)
        return (vm, api, locationProvider)
    }

    // MARK: loadForecast

    func testLoadForecastSuccessSetsForecast() async throws {
        let forecast = Fixtures.makeForecast(activities: [Fixtures.makeActivity(days: [Fixtures.makeDay(dayIndex: 0)])])
        let (vm, api, _) = makeVM(result: .success(forecast))
        api.onFetch = { [weak vm] in
            XCTAssertEqual(vm?.isLoading, true, "isLoading must be true while the request is in flight")
        }

        await vm.loadForecast()

        XCTAssertEqual(vm.forecast?.timezone, "Asia/Dubai")
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testProviderUnavailableMapsToTransientMessage() async {
        let (vm, _, _) = makeVM(result: .failure(APIError.providerUnavailable))

        await vm.loadForecast()

        XCTAssertNil(vm.forecast)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.errorMessage, APIError.providerUnavailable.userMessage)
        XCTAssertTrue(vm.isTransientError, "a 502 is transient — the UI should suggest retrying")
    }

    func testServerErrorMapsToDistinctMessage() async {
        let (vm, _, _) = makeVM(result: .failure(APIError.serverError(statusCode: 500)))

        await vm.loadForecast()

        XCTAssertEqual(vm.errorMessage, APIError.serverError(statusCode: 500).userMessage)
        XCTAssertFalse(vm.isTransientError)
        XCTAssertNotEqual(APIError.serverError(statusCode: 500).userMessage,
                          APIError.providerUnavailable.userMessage,
                          "502 and 500 must surface differently")
    }

    func testConnectionFailureSetsErrorMessage() async {
        let (vm, _, _) = makeVM(result: .failure(URLError(.cannotConnectToHost)))

        await vm.loadForecast()

        XCTAssertNil(vm.forecast)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: location

    func testFallsBackToDubaiWhenLocationNil() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, locationProvider) = makeVM(result: .success(forecast), location: nil)

        await vm.loadForecast()

        XCTAssertTrue(locationProvider.requestLocationCalled)
        XCTAssertEqual(api.capturedLat, 25.1627)
        XCTAssertEqual(api.capturedLon, 55.2077)
    }

    func testUsesDeviceLocationWhenAvailable() async {
        let forecast = Fixtures.makeForecast(activities: [])
        let (vm, api, _) = makeVM(result: .success(forecast),
                                  location: CLLocation(latitude: 24.4539, longitude: 54.3773))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedLat, 24.4539)
        XCTAssertEqual(api.capturedLon, 54.3773)
    }

    func testSendsSeedTemplates() async {
        let (vm, api, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        await vm.loadForecast()

        XCTAssertEqual(api.capturedActivities?.map(\.id), ["cycling", "fishing-lite"])
    }

    // MARK: cardDay — soonest-actionable, not best

    func testCardDayReturnsDayZeroWhenTodayWindowed() {
        let days = [
            Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 1, endIndex: 3, duration: 2),
            Fixtures.makeDay(dayIndex: 1, rating: "perfect", startIndex: 30, endIndex: 35, duration: 5),
        ]
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        let day = vm.cardDay(for: Fixtures.makeActivity(days: days))

        XCTAssertEqual(day?.dayIndex, 0)
        XCTAssertEqual(day?.rating, "good", "soonest wins — a later Perfect must not beat an earlier Good")
    }

    func testCardDayReturnsEarliestNonNullWhenTodayNil() {
        let days = [
            Fixtures.makeDay(dayIndex: 0),
            Fixtures.makeDay(dayIndex: 1),
            Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3),
            Fixtures.makeDay(dayIndex: 3, rating: "perfect", startIndex: 80, endIndex: 90, duration: 10),
        ]
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        let day = vm.cardDay(for: Fixtures.makeActivity(days: days))

        XCTAssertEqual(day?.dayIndex, 2)
    }

    func testCardDayReturnsNilWhenAllDaysNil() {
        let days = (0..<8).map { Fixtures.makeDay(dayIndex: $0) }
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))

        XCTAssertNil(vm.cardDay(for: Fixtures.makeActivity(days: days)))
    }

    // MARK: window helpers — global indices, no per-day offset math

    func testWindowStartHourUsesGlobalIndex() async {
        let day = Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3)
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertEqual(vm.windowStartHour(for: day)?.index, 52)
    }

    func testWindowStartHourNilWhenNoIndices() async {
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [])))
        await vm.loadForecast()

        XCTAssertNil(vm.windowStartHour(for: Fixtures.makeDay(dayIndex: 1)))
    }

    func testWindowStartHourNilWhenOutOfRange() async {
        let day = Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 99, endIndex: 104, duration: 5)
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertNil(vm.windowStartHour(for: day))
    }

    func testWindowHoursReturnsHalfOpenSlice() async {
        let day = Fixtures.makeDay(dayIndex: 2, rating: "good", startIndex: 52, endIndex: 55, duration: 3)
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        let hours = vm.windowHours(for: day)

        XCTAssertEqual(hours.map(\.index), [52, 53, 54], "endIndex is exclusive")
    }

    func testWindowHoursEmptyWhenIndicesNilOrOutOfRange() async {
        let (vm, _, _) = makeVM(result: .success(Fixtures.makeForecast(activities: [], hourCount: 60)))
        await vm.loadForecast()

        XCTAssertTrue(vm.windowHours(for: Fixtures.makeDay(dayIndex: 0)).isEmpty)
        let outOfRange = Fixtures.makeDay(dayIndex: 0, rating: "good", startIndex: 58, endIndex: 70, duration: 12)
        XCTAssertTrue(vm.windowHours(for: outOfRange).isEmpty)
    }
}
