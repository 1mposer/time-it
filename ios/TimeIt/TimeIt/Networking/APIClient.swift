import Foundation

/// Seam for injecting a fake in tests and the UI-test mock.
protocol RatingFetching {
    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse
}

actor APIClient: RatingFetching {
    static let shared = APIClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRatings(lat: Double, lon: Double, activities: [ActivityInput]) async throws -> ForecastResponse {
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent(APIConfig.ratingPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RatingRequest(lat: lat, lon: lon, activities: activities))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            break
        case 502:
            throw APIError.providerUnavailable
        case 400:
            // Should be unreachable — the editor mirrors ADR-0005 — but the
            // #5b §7 backstop surfaces the structured { errors } envelope,
            // naming the offending Activity via the error path.
            throw APIError.validationRejection(body: data, activityLabels: activities.map(\.label))
                ?? APIError.serverError(statusCode: 400)
        default:
            throw APIError.serverError(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ForecastResponse.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}
